# Raptor

Isolation multi-conteneurs pour **Instagram** (`com.burbn.instagram`) — sans jailbreak (dylib injectée + re-sign Sideloadly).

Chaque conteneur = **nouvel iPhone** de A à Z : stockage (fichiers, keychain, préférences, App Groups), identifiants (IDFV, IDFA, nom d'appareil), locale/région/timezone, fake localisation, DeviceCheck/App Attest neutralisés, permissions par conteneur (l'app re-demande les autorisations comme sur un appareil neuf). Bundle-agnostic : la même architecture est rejouable sur n'importe quelle app.

Base IPA actuelle : `com.burbn.instagram 450.1.0` (`D:\IPA APP\insta.ipa`), hébergée en release `v1.0-ipa` du repo.

## Build (CI uniquement — pas de build local Windows)

Repo **public** obligatoire (runners `macos-14` gratuits uniquement en public).

```powershell
# 1) Héberger la base IPA (une fois)
gh release create v1.0-ipa --repo mpoukiarmel21-beep/raptor --title "v1.0-ipa" --notes "Base Instagram 450.1.0"
gh release upload v1.0-ipa "D:\IPA APP\insta.ipa" --repo mpoukiarmel21-beep/raptor --clobber

# 2) Builder
gh workflow run build.yml --repo mpoukiarmel21-beep/raptor --ref master -f ipa_url=v1.0-ipa
# ou URL directe :  -f ipa_url=https://github.com/.../releases/download/v1.0-ipa/insta.ipa
# ou Gofile :       -f ipa_url=https://gofile.io/d/AbCd12

# 3) Récupérer
gh run watch --repo mpoukiarmel21-beep/raptor
# -> https://github.com/mpoukiarmel21-beep/raptor/releases/download/build-<N>/raptor.ipa
```

Fallback local injection (sans build dylib) : `Scripts/inject.bat` / `Scripts/build_ipa.sh` — voir `Scripts/`.

## Architecture

- `Tweak/Source/Bootstrap.m` — `__attribute__((constructor))`, ordre de démarrage, crash logger, stale guard
- `Core/` — `RPPaths`, `RPContainer`, `RPContainerStore`
- `Isolation/` — `RPHomeRedirect`, `RPKeychainHook`, `RPPrefsHook`, `RPAppGroupHook`
- `Hardening/` — `RPHardening` (DeviceCheck/App Attest/AutoFill), `RPPermissions` (TCC synthétique per-conteneur)
- `Spoof/` — `RPDeviceIdentity` (matrice puce), `RPDeviceSpoof`, `RPLocaleSpoof`, `RPLocationSpoof`
- `Camera/` — `RPCameraFeed` + `RPCameraHook` (global `global.mov`)
- `UI/` — `RPTheme`/`RPGlass`/`RPL10n` + `RPFloatingButton`/`RPPanelVC`/`RPCreateVC`/`RPMapPickerVC`/`RPActionSheet`
- `Util/` — `RPAppRelaunch`, `RPDiagnostics`
- `vendor/fishhook/` — rebinding Mach-O (keychain + CFLocale)

## Licence

Usage personnel. Ne pas distribuer de builds contenant l'IPA d'Instagram.
