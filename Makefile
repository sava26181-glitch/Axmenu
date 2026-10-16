ARCHS = arm64
TARGET = iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AXMenu
AXMenu_FILES = axmenu.xm hooks.mm esp.mm ax_overlay.mm
AXMenu_CFLAGS = -fobjc-arc -std=c++17 -I. -Wno-error
AXMenu_FRAMEWORKS = UIKit Metal MetalKit QuartzCore Foundation
AXMenu_LDFLAGS = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
