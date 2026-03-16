ARCHS = arm64
TARGET = iphone:clang:14.5:14.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = ByteMenu
ByteMenu_FILES = Tweak.x
ByteMenu_CFLAGS = -fobjc-arc -Wno-unused-function
ByteMenu_FRAMEWORKS = UIKit Foundation
include $(THEOS)/makefiles/tweak.mk
```

3. Create a file called `control`:
```
Package: com.emder.bytemenu
Name: Byte Menu
Version: 1.2.0
Architecture: iphoneos-arm
Description: Byte Menu for Yeeps Companion
Maintainer: emder
Section: Tweaks
Depends: mobilesubstrate
```

4. Create a file called `ByteMenu.plist`:
```
{ Filter = { Bundles = ( "com.TrassGames.G2Companion" ); }; }
