# TintIcons (iOS 15, Dopamine rootless)

Тёмная плитка + цветной значок, цвета меняются в Настройки -> TintIcons.

## Сборка
Нужен Theos с поддержкой rootless (свежий master).

    cd TintIcons
    make clean package FINALPACKAGE=1
    # .deb появится в packages/ — поставьте через Filza/Sileo (Dopamine)

или `make do THEOS_DEVICE_IP=<ip>` (если настроен SSH).

## Использование
Настройки -> TintIcons -> выберите цвета/пресет -> «Применить (респринг)».

## Если иконки не изменились
Смотрите лог SpringBoard и ищите строки TintIcons:

    idevicesyslog | grep TintIcons

После респринга должны быть строки вида `hooked -[SBApplicationIcon generateIconImageWithInfo:]`.
Если ни одной строки `hooked` нет — приватные селекторы на вашей версии называются иначе;
пришлите вывод лога, и я поправлю хуки.

## Файлы
- Tweak.m                       — перекраска иконок (рантайм-хуки SpringBoard)
- tinticonsprefs/               — бандл настроек (цвета, пресеты, респринг)
- layout/.../TintIcons.plist    — запись для PreferenceLoader

## Сборка через GitHub Actions
1. Залейте проект в репозиторий GitHub (ветка main).
2. Вкладка Actions -> "Build deb" -> дождитесь зелёной галочки.
3. Скачайте артефакт `TintIcons-deb` (внутри .deb).
4. Для релиза: `git tag v1.0.0 && git push --tags` — .deb появится в Releases.

Если твик не подгружается на arm64e, пересоберите с Xcode 14.x (на macos-13 / локально):
в Dopamine arm64e-код от новых Xcode иногда не инжектится.
