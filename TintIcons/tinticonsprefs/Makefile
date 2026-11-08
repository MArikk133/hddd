TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TintIconsPrefs

TintIconsPrefs_FILES = TIRootListController.m
TintIconsPrefs_FRAMEWORKS = UIKit
TintIconsPrefs_PRIVATE_FRAMEWORKS = Preferences
TintIconsPrefs_INSTALL_PATH = /Library/PreferenceBundles
TintIconsPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
