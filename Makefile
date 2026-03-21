ARCHS = arm64
TARGET = iphone:clang:14.5:14.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = ByteMenu
ByteMenu_FILES = Tweak.x
ByteMenu_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-arc-performSelector-leaks -Wno-unused-variable
ByteMenu_FRAMEWORKS = UIKit Foundation
include $(THEOS)/makefiles/tweak.mk
