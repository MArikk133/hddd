export THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TintIcons

TintIcons_FILES = Tweak.m
TintIcons_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
TintIcons_FRAMEWORKS = UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += tinticonsprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
