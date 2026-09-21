TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES := TikTok
THEOS_PACKAGE_DIR_NAME = DEBIAN
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokCommentBot
TikTokCommentBot_FILES = Tweak.x
TikTokCommentBot_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
