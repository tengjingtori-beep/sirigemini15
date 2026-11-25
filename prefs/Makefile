include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SiriGemini15Prefs
SiriGemini15Prefs_FILES = SGPrefsListController.m ../SGGemini.m
SiriGemini15Prefs_INSTALL_PATH = /Library/PreferenceBundles
SiriGemini15Prefs_FRAMEWORKS = UIKit AVFoundation
# The iPhoneOS SDK ships the Preferences headers but no link stub for
# the private Preferences framework, so linking fails on CI.
# Resolve PSListController at load time instead: the bundle is only
# ever loaded inside the Settings app, where Preferences is present.
SiriGemini15Prefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
SiriGemini15Prefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/SiriGemini15Prefs.plist
	# VoiceChat15 0.1.0 bug: the entry plist, Root.plist and the bundle
	# directory were staged with 640/750 permissions. The Settings app
	# runs as mobile and could not read/traverse them, so
	# PreferenceLoader skipped this pane and it never appeared in
	# Settings. Force world-readable perms on everything Settings
	# must read.
	chmod 755 $(THEOS_STAGING_DIR)/Library/PreferenceBundles/SiriGemini15Prefs.bundle
	chmod 644 $(THEOS_STAGING_DIR)/Library/PreferenceBundles/SiriGemini15Prefs.bundle/Root.plist
	chmod 644 $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/SiriGemini15Prefs.plist
