TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES := TikTok
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokCommentBot
TikTokCommentBot_FILES = Tweak.x
TikTokCommentBot_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
