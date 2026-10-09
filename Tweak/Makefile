ARCHS = arm64
TARGET = iphone:clang:latest:16.3
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# LIBRARY (not TWEAK) — we must not link CydiaSubstrate.
# CI asserts otool -L has no "substrate".
LIBRARY_NAME = raptor
raptor_FILES = \
  Source/Bootstrap.m \
  Source/Core/RPPaths.m Source/Core/RPContainer.m Source/Core/RPContainerStore.m \
  Source/Isolation/RPHomeRedirect.m Source/Isolation/RPKeychainHook.m Source/Isolation/RPPrefsHook.m Source/Isolation/RPAppGroupHook.m \
  Source/Hardening/RPHardening.m Source/Hardening/RPPermissions.m \
  Source/Spoof/RPDeviceIdentity.m Source/Spoof/RPDeviceSpoof.m Source/Spoof/RPLocaleSpoof.m Source/Spoof/RPLocationSpoof.m \
  Source/Camera/RPCameraFeed.m Source/Camera/RPCameraHook.m \
  Source/UI/RPTheme.m Source/UI/RPGlass.m Source/UI/RPL10n.m Source/UI/RPActionSheet.m Source/UI/RPFloatingButton.m Source/UI/RPListPickerVC.m Source/UI/RPPanelVC.m Source/UI/RPCreateVC.m Source/UI/RPMapPickerVC.m \
  Source/Util/RPAppRelaunch.m Source/Util/RPDiagnostics.m \
  Source/vendor/fishhook/fishhook.c

raptor_CFLAGS = -fobjc-arc -ISource -ISource/Core -ISource/Isolation -ISource/Hardening -ISource/Spoof -ISource/Camera -ISource/UI -ISource/Util -ISource/vendor \
  -Wno-deprecated-declarations -Wno-unused-variable -Wno-error=unguarded-availability-new

raptor_FRAMEWORKS = UIKit CoreLocation MapKit Security AVFoundation CoreMedia CoreVideo CoreImage ImageIO PhotosUI AdSupport

include $(THEOS_MAKE_PATH)/library.mk
