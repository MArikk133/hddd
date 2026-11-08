#import "TIRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kDomain = @"com.user.tinticons";
#define kRespringNote CFSTR("com.user.tinticons/respring")

#pragma mark - Хелперы

static NSString *TIDefaultHex(NSString *key) {
	return [key isEqualToString:@"glyphColor"] ? @"#F2A9BE" : @"#232326";
}

static NSString *TIGetString(NSString *key) {
	id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain));
	return [v isKindOfClass:[NSString class]] ? v : TIDefaultHex(key);
}

static void TISetValue(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
}

static UIColor *TIColorFromHex(NSString *hex) {
	NSString *h = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
	unsigned int v = 0;
	[[NSScanner scannerWithString:h] scanHexInt:&v];
	return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
	                       green:((v >> 8) & 0xFF) / 255.0
	                        blue:(v & 0xFF) / 255.0
	                       alpha:1.0];
}

static NSString *TIHexFromColor(UIColor *c) {
	CGFloat r = 0, g = 0, b = 0, a = 0;
	if (![c getRed:&r green:&g blue:&b alpha:&a]) {
		CGFloat w = 0;
		if ([c getWhite:&w alpha:&a]) r = g = b = w;
	}
	r = fmin(fmax(r, 0), 1); g = fmin(fmax(g, 0), 1); b = fmin(fmax(b, 0), 1);
	return [NSString stringWithFormat:@"#%02X%02X%02X",
	        (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}

static NSArray<NSDictionary *> *TIPresets(void) {
	return @[
		@{@"n": @"Розовый (как на фото)", @"g": @"#F2A9BE", @"b": @"#232326"},
		@{@"n": @"Мятный",                @"g": @"#8FE3C5", @"b": @"#1E2422"},
		@{@"n": @"Голубой",               @"g": @"#8EC5FF", @"b": @"#1C2128"},
		@{@"n": @"Янтарный",              @"g": @"#FFB86B", @"b": @"#2A2420"},
		@{@"n": @"Сиреневый",             @"g": @"#C9A7FF", @"b": @"#221F2B"},
		@{@"n": @"Монохром",              @"g": @"#F2F2F7", @"b": @"#1C1C1E"},
	];
}

#pragma mark - Контроллер

@implementation TIRootListController

- (PSSpecifier *)switchNamed:(NSString *)name key:(NSString *)key def:(BOOL)def {
	PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
	                                                 target:self
	                                                    set:@selector(setPreferenceValue:specifier:)
	                                                    get:@selector(readPreferenceValue:)
	                                                 detail:Nil
	                                                   cell:PSSwitchCell
	                                                   edit:Nil];
	[sp setProperty:kDomain forKey:@"defaults"];
	[sp setProperty:key forKey:@"key"];
	[sp setProperty:@(def) forKey:@"default"];
	return sp;
}

- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action {
	PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
	                                                 target:self
	                                                    set:NULL
	                                                    get:NULL
	                                                 detail:Nil
	                                                   cell:PSButtonCell
	                                                   edit:Nil];
	sp.buttonAction = action;
	return sp;
}

- (NSArray *)specifiers {
	if (_specifiers) return _specifiers;
	NSMutableArray *s = [NSMutableArray array];

	// --- Основное ---
	PSSpecifier *g1 = [PSSpecifier groupSpecifierWithName:@"Основное"];
	[g1 setProperty:@"Изменения вступают в силу после респринга (кнопка внизу)." forKey:@"footerText"];
	[s addObject:g1];
	[s addObject:[self switchNamed:@"Включить" key:@"enabled" def:YES]];

	// --- Цвета ---
	PSSpecifier *g2 = [PSSpecifier groupSpecifierWithName:@"Цвета"];
	[g2 setProperty:@"Нажмите на строку, чтобы выбрать цвет. Значок — это цвет рисунка иконки, плитка — цвет фона под ним." forKey:@"footerText"];
	[s addObject:g2];

	PSSpecifier *c1 = [self buttonNamed:@"Цвет значка" action:@selector(pickColor:)];
	[c1 setProperty:@"glyphColor" forKey:@"colorKey"];
	[s addObject:c1];

	PSSpecifier *c2 = [self buttonNamed:@"Цвет плитки" action:@selector(pickColor:)];
	[c2 setProperty:@"bgColor" forKey:@"colorKey"];
	[s addObject:c2];

	// --- Пресеты ---
	PSSpecifier *g3 = [PSSpecifier groupSpecifierWithName:@"Пресеты"];
	[s addObject:g3];
	NSArray *presets = TIPresets();
	for (NSUInteger i = 0; i < presets.count; i++) {
		PSSpecifier *p = [self buttonNamed:presets[i][@"n"] action:@selector(applyPreset:)];
		[p setProperty:@(i) forKey:@"presetIndex"];
		[s addObject:p];
	}

	// --- Чувствительность ---
	PSSpecifier *g4 = [PSSpecifier groupSpecifierWithName:@"Чувствительность выделения значка"];
	[g4 setProperty:@"Меньше — в значок попадает больше деталей (и шума от градиентов). Больше — только самые контрастные элементы. По умолчанию 0.22." forKey:@"footerText"];
	[s addObject:g4];
	PSSpecifier *sl = [PSSpecifier preferenceSpecifierNamed:@"Чувствительность"
	                                                 target:self
	                                                    set:@selector(setPreferenceValue:specifier:)
	                                                    get:@selector(readPreferenceValue:)
	                                                 detail:Nil
	                                                   cell:PSSliderCell
	                                                   edit:Nil];
	[sl setProperty:kDomain forKey:@"defaults"];
	[sl setProperty:@"threshold" forKey:@"key"];
	[sl setProperty:@0.22 forKey:@"default"];
	[sl setProperty:@0.08 forKey:@"min"];
	[sl setProperty:@0.50 forKey:@"max"];
	[sl setProperty:@YES forKey:@"showValue"];
	[s addObject:sl];

	// --- Дополнительно ---
	PSSpecifier *g5 = [PSSpecifier groupSpecifierWithName:@"Дополнительно"];
	[g5 setProperty:@"Иконки, которые занимают весь кадр (фото, сложные арты), нельзя разделить на плитку и значок. Если включено — они окрашиваются по яркости, как «Тонированные» иконки iOS 18 (с сохранением деталей), если выключено — остаются как есть. Градиент делает плитку чуть светлее сверху и темнее снизу." forKey:@"footerText"];
	[s addObject:g5];
	[s addObject:[self switchNamed:@"Тоновый режим для сложных иконок" key:@"fallback" def:YES]];
	[s addObject:[self switchNamed:@"Градиент плитки (как в iOS 18)" key:@"gradient" def:YES]];

	// --- Действия ---
	PSSpecifier *g6 = [PSSpecifier emptyGroupSpecifier];
	[s addObject:g6];
	[s addObject:[self buttonNamed:@"Применить (респринг)" action:@selector(respring:)]];
	[s addObject:[self buttonNamed:@"Сбросить настройки" action:@selector(resetPrefs:)]];

	_specifiers = s;
	return _specifiers;
}

#pragma mark Плашки-образцы цвета

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	PSSpecifier *sp = [self specifierAtIndexPath:indexPath];

	NSString *key = [sp propertyForKey:@"colorKey"];
	NSNumber *preset = [sp propertyForKey:@"presetIndex"];

	if (key) {
		UIView *sw = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
		sw.backgroundColor = TIColorFromHex(TIGetString(key));
		sw.layer.cornerRadius = 15;
		sw.layer.borderWidth = 1;
		sw.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.5].CGColor;
		cell.accessoryView = sw;
	} else if (preset) {
		NSDictionary *p = TIPresets()[preset.unsignedIntegerValue];
		UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
		tile.backgroundColor = TIColorFromHex(p[@"b"]);
		tile.layer.cornerRadius = 7;
		UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 14, 14)];
		dot.backgroundColor = TIColorFromHex(p[@"g"]);
		dot.layer.cornerRadius = 7;
		[tile addSubview:dot];
		cell.accessoryView = tile;
	}
	return cell;
}

#pragma mark Действия

- (void)pickColor:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"colorKey"];
	if (!key) return;
	self.editingKey = key;

	UIColorPickerViewController *pc = [[UIColorPickerViewController alloc] init];
	pc.delegate = self;
	pc.supportsAlpha = NO;
	pc.title = specifier.name;
	pc.selectedColor = TIColorFromHex(TIGetString(key));
	[self presentViewController:pc animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)vc {
	if (!self.editingKey) return;
	TISetValue(self.editingKey, TIHexFromColor(vc.selectedColor));
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
	if (self.editingKey) TISetValue(self.editingKey, TIHexFromColor(vc.selectedColor));
	[self reloadSpecifiers];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self reloadSpecifiers]; // обновить плашки после закрытия пикера свайпом
}

- (void)applyPreset:(PSSpecifier *)specifier {
	NSNumber *idx = [specifier propertyForKey:@"presetIndex"];
	if (!idx) return;
	NSDictionary *p = TIPresets()[idx.unsignedIntegerValue];
	TISetValue(@"glyphColor", p[@"g"]);
	TISetValue(@"bgColor", p[@"b"]);
	[self reloadSpecifiers];
}

- (void)resetPrefs:(PSSpecifier *)specifier {
	for (NSString *k in @[@"enabled", @"fallback", @"gradient", @"threshold", @"glyphColor", @"bgColor"])
		TISetValue(k, nil);
	[self reloadSpecifiers];
}

- (void)respring:(PSSpecifier *)specifier {
	CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
	                                     kRespringNote, NULL, NULL, YES);
}

@end
