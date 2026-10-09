# AGENT-HANDOFF — raptor

## État actuel
Repo public https://github.com/mpoukiarmel21-beep/raptor (master), base insta.ipa 450.1.0 (D:\IPA APP\insta.ipa). Rewrite 100% from scratch — aucun code whaminsta copié, tout RP*.

## En cours
Build initial en préparation (tout Bootstrap/Core/Isolation/Spoof/Hardening/Camera/UI from scratch vient d'être écrit).

## Prochaine étape
Push squelette + trigger CI build v1.0-ipa.

## Blocages / risques
- Aucun build local (Windows, pas de Theos) — CI macos-14 uniquement.
- Repo doit rester public.

## Journal
- 2026-10-09 — Raptor from scratch : Bootstrap, RPPaths/RPContainer/RPContainerStore, RPHomeRedirect/RPKeychainHook/RPPrefsHook/RPAppGroupHook, RPDeviceIdentity (29 modèles, puce stricte), RPDeviceSpoof (IDFV/IDFA/name), RPLocaleSpoof, RPLocationSpoof (gInDelivery), RPHardening (DeviceCheck/AppAttest/AutoFill + APNs suppress + ATT NotDetermined), RPPermissions (CLLocation/PHPhoto/AVCapture per-conteneur), RPCameraFeed/Hook, RPTheme/RPGlass/RPL10n/RPActionSheet/RPFloatingButton/RPListPickerVC/RPMapPickerVC/RPCreateVC/RPPanelVC, RPDiagnostics/RPAppRelaunch, fishhook vendor. Build.yml + Makefile (LIBRARY raptor, iOS 16.3).
