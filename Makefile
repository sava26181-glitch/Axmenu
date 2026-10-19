ARCHS = arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AXHideJB
AXHideJB_FILES = axhidejb.xm hide.mm fishhook.c
AXHideJB_CFLAGS = -fobjc-arc -I.

include $(THEOS)/makefiles/tweak.mk
