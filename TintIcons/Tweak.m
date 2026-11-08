// TintIcons — тёмная плитка + цветной глиф (как "Tinted" иконки), iOS 15, rootless.
//
// Как это работает:
//   1. Хукаем генерацию картинки иконки в SpringBoard (SBIcon / SBHIconImageCache / SBIconImageView).
//   2. Для каждой иконки оцениваем цвет фона (по левому/правому краю, построчно — это
//      учитывает вертикальные градиенты), затем всё, что от фона отличается — это "глиф".
//   3. Рисуем новую иконку: фон = ваш цвет плитки, глиф = ваш цвет значка.
//   4. Для "сложных" иконок (на весь кадр, где глиф не выделить) — дуотон по яркости.

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <math.h>

#define kPrefsDomain  CFSTR("com.user.tinticons")
#define kRespringNote CFSTR("com.user.tinticons/respring")

// struct SBIconImageInfo из SpringBoardHome (iOS 14+)
typedef struct {
	CGSize  size;
	CGFloat scale;
	CGFloat continuousCornerRadius;
} TIIconImageInfo;

#pragma mark - Настройки

static BOOL  gEnabled   = YES;
static BOOL  gFallback  = YES;
static float gThreshold = 0.22f;
static float gFg[3]     = {0.949f, 0.663f, 0.745f}; // #F2A9BE — цвет глифа
static float gBg[3]     = {0.137f, 0.137f, 0.149f}; // #232326 — цвет плитки

static BOOL TIParseHex(id s, float out[3]) {
	if (![s isKindOfClass:[NSString class]]) return NO;
	NSString *h = [s hasPrefix:@"#"] ? [s substringFromIndex:1] : s;
	if (h.length != 6) return NO;
	unsigned int v = 0;
	if (![[NSScanner scannerWithString:h] scanHexInt:&v]) return NO;
	out[0] = ((v >> 16) & 0xFF) / 255.f;
	out[1] = ((v >> 8)  & 0xFF) / 255.f;
	out[2] = ( v        & 0xFF) / 255.f;
	return YES;
}

static id TIPref(CFStringRef key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue(key, kPrefsDomain));
}

static void TILoadPrefs(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	id v;
	if ((v = TIPref(CFSTR("enabled"))))    gEnabled   = [v boolValue];
	if ((v = TIPref(CFSTR("fallback"))))   gFallback  = [v boolValue];
	if ((v = TIPref(CFSTR("threshold"))))  gThreshold = fminf(fmaxf([v floatValue], 0.08f), 0.55f);
	if ((v = TIPref(CFSTR("glyphColor")))) TIParseHex(v, gFg);
	if ((v = TIPref(CFSTR("bgColor"))))    TIParseHex(v, gBg);
}

#pragma mark - Обработка картинки

static char kTIProcessed;
static NSMapTable *gCache; // weak(source) -> strong(result)

static inline float TISmooth(float e0, float e1, float x) {
	float t = fminf(fmaxf((x - e0) / (e1 - e0), 0.f), 1.f);
	return t * t * (3.f - 2.f * t);
}

static inline float TILum(const float *c) {
	return 0.299f * c[0] + 0.587f * c[1] + 0.114f * c[2];
}

// Покрытие пикселя скруглённым прямоугольником (SDF с антиалиасингом)
static inline float TIRoundRectCover(float x, float y, float w, float h, float r) {
	float px = fabsf(x + 0.5f - w * 0.5f) - (w * 0.5f - r);
	float py = fabsf(y + 0.5f - h * 0.5f) - (h * 0.5f - r);
	float qx = fmaxf(px, 0.f), qy = fmaxf(py, 0.f);
	float d  = sqrtf(qx * qx + qy * qy) + fminf(fmaxf(px, py), 0.f) - r;
	return fminf(fmaxf(0.5f - d, 0.f), 1.f);
}

static UIImage *TIRender(UIImage *src) {
	CGImageRef cg = src.CGImage;
	if (!cg) return src;

	size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
	if (w < 24 || h < 24 || w > 640 || h > 640) return src;
	if (fabs((double)w / (double)h - 1.0) > 0.06) return src; // иконки квадратные

	const size_t N = w * h;
	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	uint8_t *px  = (uint8_t *)calloc(N, 4);
	float   *mem = (float *)calloc(N * 5 + h * 4, sizeof(float));
	if (!cs || !px || !mem) {
		if (cs) CGColorSpaceRelease(cs);
		free(px); free(mem);
		return src;
	}

	CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, w * 4, cs,
		kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	if (!ctx) {
		CGColorSpaceRelease(cs); free(px); free(mem);
		return src;
	}
	CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);

	float *rgb = mem;            // N*3  цвет без премультипликации
	float *al  = mem + N * 3;    // N    альфа исходника
	float *gl  = mem + N * 4;    // N    "глиф-альфа"
	float *bgr = mem + N * 5;    // h*4  цвет фона по строкам (+флаг валидности)

	// --- распаковка ---
	for (size_t i = 0; i < N; i++) {
		float a = px[i * 4 + 3] / 255.f;
		al[i] = a;
		if (a > 0.001f) {
			for (int k = 0; k < 3; k++)
				rgb[i * 3 + k] = fminf(px[i * 4 + k] / 255.f / a, 1.f);
		}
	}

	// иконка без маски (углы непрозрачны) -> сами скруглим
	BOOL unmasked = al[0] > 0.98f && al[w - 1] > 0.98f &&
	                al[(h - 1) * w] > 0.98f && al[N - 1] > 0.98f;

	// --- оценка фона построчно (полосы у левого и правого края) ---
	size_t a0 = (size_t)lroundf(w * 0.05f), a1 = (size_t)lroundf(w * 0.09f);
	if (a1 <= a0) a1 = a0 + 1;
	long first = -1, last = -1;
	for (size_t y = 0; y < h; y++) {
		float s[3] = {0, 0, 0}; int n = 0;
		for (int side = 0; side < 2; side++) {
			for (size_t xx = a0; xx < a1; xx++) {
				size_t x = side ? (w - 1 - xx) : xx;
				size_t i = y * w + x;
				if (al[i] > 0.98f) {
					s[0] += rgb[i * 3]; s[1] += rgb[i * 3 + 1]; s[2] += rgb[i * 3 + 2];
					n++;
				}
			}
		}
		if (n) {
			bgr[y * 4 + 0] = s[0] / n; bgr[y * 4 + 1] = s[1] / n; bgr[y * 4 + 2] = s[2] / n;
			bgr[y * 4 + 3] = 1.f;
			if (first < 0) first = (long)y;
			last = (long)y;
		}
	}
	if (first < 0) { // фон оценить не удалось
		CGContextRelease(ctx); CGColorSpaceRelease(cs); free(px); free(mem);
		return src;
	}
	for (long y = 0; y < first; y++)          memcpy(&bgr[y * 4], &bgr[first * 4], 4 * sizeof(float));
	for (long y = last + 1; y < (long)h; y++) memcpy(&bgr[y * 4], &bgr[last * 4],  4 * sizeof(float));
	for (long y = first + 1; y <= last; y++)
		if (bgr[y * 4 + 3] < 0.5f) memcpy(&bgr[y * 4], &bgr[(y - 1) * 4], 4 * sizeof(float));

	// --- маска глифа ---
	float t0 = fmaxf(gThreshold - 0.07f, 0.01f), t1 = gThreshold + 0.07f;
	double covSum = 0, aSum = 0;
	for (size_t y = 0; y < h; y++) {
		const float *b = &bgr[y * 4];
		for (size_t x = 0; x < w; x++) {
			size_t i = y * w + x;
			if (al[i] < 0.01f) { gl[i] = 0; continue; }
			float dr = rgb[i * 3] - b[0], dg = rgb[i * 3 + 1] - b[1], db = rgb[i * 3 + 2] - b[2];
			float d  = sqrtf(0.30f * dr * dr + 0.59f * dg * dg + 0.11f * db * db);
			float g  = TISmooth(t0, t1, d);
			gl[i] = g;
			covSum += g * al[i];
			aSum   += al[i];
		}
	}
	float coverage = aSum > 0 ? (float)(covSum / aSum) : 0.f;
	BOOL complex = coverage > 0.70f; // глиф занимает почти всё -> иконка "на весь кадр"

	if (complex && !gFallback) {
		CGContextRelease(ctx); CGColorSpaceRelease(cs); free(px); free(mem);
		return src;
	}

	float bgAvg[3] = {0, 0, 0};
	for (size_t y = 0; y < h; y++)
		for (int k = 0; k < 3; k++) bgAvg[k] += bgr[y * 4 + k];
	for (int k = 0; k < 3; k++) bgAvg[k] /= (float)h;
	float bgL    = TILum(bgAvg);
	BOOL invert  = bgL > 0.5f;                 // светлый фон -> инвертируем яркость
	float bgLn   = invert ? 1.f - bgL : bgL;
	float span   = fmaxf(1.f - bgLn, 0.2f);
	float radius = 0.2237f * (float)w;

	// --- сборка результата ---
	for (size_t y = 0; y < h; y++) {
		for (size_t x = 0; x < w; x++) {
			size_t i = y * w + x;
			float a = al[i];
			if (unmasked) a *= TIRoundRectCover((float)x, (float)y, (float)w, (float)h, radius);

			float t;
			if (complex) {
				float L = TILum(&rgb[i * 3]);
				if (invert) L = 1.f - L;
				t = fminf(fmaxf((L - bgLn) / span, 0.f), 1.f);
			} else {
				t = gl[i];
			}
			for (int k = 0; k < 3; k++) {
				float c = gBg[k] + (gFg[k] - gBg[k]) * t;
				px[i * 4 + k] = (uint8_t)lroundf(fminf(fmaxf(c, 0.f), 1.f) * a * 255.f);
			}
			px[i * 4 + 3] = (uint8_t)lroundf(fminf(fmaxf(a, 0.f), 1.f) * 255.f);
		}
	}

	UIImage *result = src;
	CGImageRef out = CGBitmapContextCreateImage(ctx);
	if (out) {
		result = [UIImage imageWithCGImage:out scale:src.scale orientation:UIImageOrientationUp];
		CGImageRelease(out);
	}

	CGContextRelease(ctx);
	CGColorSpaceRelease(cs);
	free(px);
	free(mem);
	return result ?: src;
}

static id TIProcessAny(id obj) {
	if (!gEnabled || ![obj isKindOfClass:[UIImage class]]) return obj;
	UIImage *src = obj;
	if (objc_getAssociatedObject(src, &kTIProcessed)) return src;

	@synchronized (gCache) {
		UIImage *hit = [gCache objectForKey:src];
		if (hit) return hit;
	}
	UIImage *out = TIRender(src);
	objc_setAssociatedObject(out, &kTIProcessed, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (out != src) { // не кэшируем src->src, иначе таблица держала бы ключ сильной ссылкой
		@synchronized (gCache) {
			[gCache setObject:out forKey:src];
		}
	}
	return out;
}

#pragma mark - Рантайм-хуки (с проверкой сигнатур, чтобы не уронить SpringBoard)

// Метод объявлен именно в этом классе, а не унаследован
static BOOL TIDeclares(Class cls, SEL sel) {
	if (!cls) return NO;
	Method m = class_getInstanceMethod(cls, sel);
	if (!m) return NO;
	Class sup = class_getSuperclass(cls);
	Method sm = sup ? class_getInstanceMethod(sup, sel) : NULL;
	return !sm || method_getImplementation(sm) != method_getImplementation(m);
}

static BOOL TIReturnsObject(Method m) {
	char *rt = method_copyReturnType(m);
	BOOL ok = rt && rt[0] == '@';
	free(rt);
	return ok;
}

// -(UIImage *)foo
static void TIHookNoArg(Class cls, const char *name) {
	SEL sel = sel_registerName(name);
	if (!TIDeclares(cls, sel)) return;
	Method m = class_getInstanceMethod(cls, sel);
	if (!TIReturnsObject(m) || method_getNumberOfArguments(m) != 2) return;

	IMP orig = method_getImplementation(m);
	IMP repl = imp_implementationWithBlock(^id(id self) {
		return TIProcessAny(((id (*)(id, SEL))orig)(self, sel));
	});
	method_setImplementation(m, repl);
	NSLog(@"[TintIcons] hooked -[%s %s]", class_getName(cls), name);
}

// -(UIImage *)foo:(id)icon
static void TIHookObjArg(Class cls, const char *name) {
	SEL sel = sel_registerName(name);
	if (!TIDeclares(cls, sel)) return;
	Method m = class_getInstanceMethod(cls, sel);
	if (!TIReturnsObject(m) || method_getNumberOfArguments(m) != 3) return;
	char t[32] = {0};
	method_getArgumentType(m, 2, t, sizeof(t));
	if (t[0] != '@') return;

	IMP orig = method_getImplementation(m);
	IMP repl = imp_implementationWithBlock(^id(id self, id a) {
		return TIProcessAny(((id (*)(id, SEL, id))orig)(self, sel, a));
	});
	method_setImplementation(m, repl);
	NSLog(@"[TintIcons] hooked -[%s %s]", class_getName(cls), name);
}

// -(UIImage *)generateIconImageWithInfo:(SBIconImageInfo)info
static void TIHookGenerate(Class cls) {
	SEL sel = sel_registerName("generateIconImageWithInfo:");
	if (!TIDeclares(cls, sel)) return;
	Method m = class_getInstanceMethod(cls, sel);
	if (!TIReturnsObject(m) || method_getNumberOfArguments(m) != 3) return;
	char t[128] = {0};
	method_getArgumentType(m, 2, t, sizeof(t));
	NSUInteger sz = 0;
	NSGetSizeAndAlignment(t, &sz, NULL);
	if (sz != sizeof(TIIconImageInfo)) return; // структура другая — не трогаем

	IMP orig = method_getImplementation(m);
	IMP repl = imp_implementationWithBlock(^id(id self, TIIconImageInfo info) {
		return TIProcessAny(((id (*)(id, SEL, TIIconImageInfo))orig)(self, sel, info));
	});
	method_setImplementation(m, repl);
	NSLog(@"[TintIcons] hooked -[%s generateIconImageWithInfo:]", class_getName(cls));
}

#pragma mark - Respring по кнопке из настроек

static void TIRespringCallback(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef ui) {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIApplication *app = [UIApplication sharedApplication];
		SEL s = NSSelectorFromString(@"_relaunchSpringBoardNow");
		if ([app respondsToSelector:s]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			[app performSelector:s];
#pragma clang diagnostic pop
		} else {
			exit(0);
		}
	});
}

#pragma mark - Старт

__attribute__((constructor))
static void TIInit(void) {
	@autoreleasepool {
		TILoadPrefs();

		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
			TIRespringCallback, kRespringNote, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

		if (!gEnabled) return;

		gCache = [NSMapTable mapTableWithKeyOptions:(NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality)
		                               valueOptions:NSPointerFunctionsStrongMemory];

		// 1) генерация картинки иконки (основной путь на iOS 14/15)
		const char *iconClasses[] = {
			"SBIcon", "SBLeafIcon", "SBApplicationIcon", "SBBookmarkIcon",
			"SBClockApplicationIcon", "SBCalendarApplicationIcon", "SBWidgetIcon"
		};
		for (size_t i = 0; i < sizeof(iconClasses) / sizeof(*iconClasses); i++)
			TIHookGenerate(objc_getClass(iconClasses[i]));

		// 2) кэш картинок иконок (на случай, если путь выше не сработал)
		Class cache = objc_getClass("SBHIconImageCache");
		TIHookObjArg(cache, "imageForIcon:");
		TIHookObjArg(cache, "cachedImageForIcon:");

		// 3) сам вью иконки — запасной вариант
		Class iv = objc_getClass("SBIconImageView");
		TIHookNoArg(iv, "contentsImage");
		TIHookNoArg(iv, "squareContentsImage");

		NSLog(@"[TintIcons] loaded, fg=%.2f/%.2f/%.2f bg=%.2f/%.2f/%.2f thr=%.2f",
			gFg[0], gFg[1], gFg[2], gBg[0], gBg[1], gBg[2], gThreshold);
	}
}
