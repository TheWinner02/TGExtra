ARCHS = arm64 arm64e
TARGET = iphone:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TGExtra

$(TWEAK_NAME)_FILES = $(shell find Sources \( -name '*.swift' -o -name '*.m' -o -name '*.xm' \))
$(TWEAK_NAME)_SWIFTFLAGS = -ISources/tgapiC/include
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -ISources/tgapiC/include -Wno-deprecated-declarations
$(TWEAK_NAME)_FRAMEWORKS = CoreServices
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal
$(TWEAK_NAME)_RESOURCE_FILES = Sources/tgapi/Resources

# Copy TGExtra.bundle manually during the packaging step
after-stage::
	@echo ">>> Copying Choco.bundle into .deb package..."
	@mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support/TGExtra
	@cp -a TGExtra.bundle $(THEOS_STAGING_DIR)/Library/Application\ Support/TGExtra

include $(THEOS_MAKE_PATH)/tweak.mk
