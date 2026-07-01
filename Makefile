TARGET = noad.dylib
ARCHS = arm64
SDK = iphoneos
THEOS_DEVICE_IP = localhost -p 2222

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = noad
noad_FILES = Tweak.xm HookAdSDK.m HookMotion.m
noad_FRAMEWORKS = Foundation UIKit CoreMotion
noad_LDFLAGS = -lz -lobjc

include $(THEOS_MAKE_PATH)/library.mk

package::
	@echo "Build output: .theos/obj/arm64/noad.dylib"
	@echo "Install via TrollStore or inject into IPA"
