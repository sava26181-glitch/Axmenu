ARCHS = arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AXMenu
AXMenu_FILES = axmenu.xm hooks.mm esp.mm hide.mm fishhook.c
AXMenu_CFLAGS = -fobjc-arc -I.
AXMenu_FRAMEWORKS = UIKit Foundation

include $(THEOS)/makefiles/tweak.mk
