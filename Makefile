# Modern rootless jailbreaks (Dopamine / ElleKit).
export THEOS_PACKAGE_SCHEME = rootless
export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e

DEBUG = 0
FINALPACKAGE = 1
THEOS_PACKAGE_DIR = Releases
INSTALL_TARGET_PROCESSES = TweakSettings

include $(THEOS)/makefiles/common.mk

XCODEPROJ_NAME = TweakSettings
TweakSettings_XCODEFLAGS = IPHONEOS_DEPLOYMENT_TARGET=15.0
TweakSettings_XCODEFLAGS += HEADER_SEARCH_PATHS='$(THEOS_VENDOR_INCLUDE_PATH)/libroot'
TweakSettings_XCODEFLAGS += LIBRARY_SEARCH_PATHS='$(THEOS_VENDOR_LIBRARY_PATH)/iphone/rootless'
TweakSettings_XCODEFLAGS += OTHER_LDFLAGS='-lroot'
TweakSettings_XCODEFLAGS += MARKETING_VERSION='$(THEOS_PACKAGE_BASE_VERSION)' CURRENT_PROJECT_VERSION='$(THEOS_PACKAGE_BASE_VERSION)'
TweakSettings_XCODEOPTS = -derivedDataPath $(THEOS_PROJECT_DIR)/build/DerivedData
TweakSettings_CODESIGN_FLAGS = -SResources/entitlements.plist

include $(THEOS_MAKE_PATH)/xcodeproj.mk

SUBPROJECTS += TweakSettings-Utility
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	chmod 0755 "$(THEOS_STAGING_DIR)/Applications/TweakSettings.app/TweakSettings"
	chmod 4755 "$(THEOS_STAGING_DIR)/usr/bin/tweaksettings-utility"

after-install::
	install.exec "$(THEOS_PACKAGE_INSTALL_PREFIX)/usr/bin/uicache -p $(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/TweakSettings.app"

# Some versions of Perl Archive::Tar used by dm.pl update owner names only.
# Normalize numeric IDs as well, without requiring sudo or changing host files.
after-package::
	python3 scripts/normalize_deb_ownership.py "$(__THEOS_LAST_PACKAGE_FILENAME)"
