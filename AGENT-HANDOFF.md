# AGENT-HANDOFF — raptor

## État actuel
Repo public https://github.com/mpoukiarmel21-beep/raptor (master). Dernier build livré = **build-15** (base 442.0.0 InstaVault).
Nouvelle base cible : **IG 449.0.0 nettoyée** depuis `D:\IPA APP\RyukGram-No-Plugins_1.4.5_IG449.0.0.ipa` (tweak RyukGram retiré, `.app` officiel conservé).

## En cours
OpenCode, 2026-10-11 : upload de la base 449 nettoyée vers la release `base-449` (12 morceaux `base449.part00..part11`, ~54 KB/s → ~75 min). Build CI à lancer après.

## Prochaine étape
1. Vérifier fin upload (`D:\Temp\opencode\upload449.log` = "ALL DONE").
2. `gh workflow run build.yml --repo mpoukiarmel21-beep/raptor --ref master -f ipa_url="parts:mpoukiarmel21-beep/raptor/base-449/base449.part"`.
3. Poller jusqu'au SUCCESS, livrer `https://github.com/mpoukiarmel21-beep/raptor/releases/download/build-<N>/raptor.ipa`.

## Blocages / risques
- Ligne très lente (~54 KB/s) → base 245.7 MB envoyée par morceaux (mode `parts:` du workflow).
- Aucun build local (Windows, pas de Theos) — CI macos-14 uniquement. Repo doit rester public.

## Journal
- 2026-10-11 — **Décomposition RyukGram** : IG 449.0.0 (`com.burbn.instagram`, build 1077525814) + 4 dylibs injectés en `LC_LOAD_WEAK_DYLIB` (`RyukGram.dylib`, `NoPluginsPatch.dylib`, `FLEXing.dylib`, `libflex.dylib`) + `CydiaSubstrate.framework` + `RyukGram.bundle`. Leur anti-crash = hook safe-mode natif IG (`IGSafeModeChecker initWithInstacrashCounterProvider:crashThreshold:`) + launch-guard perso (3 crashs → overrides off, valeurs gardées) ; spoof = `device_id/fdid/mid/mid_header`, blocage DeviceCheck+App Attest, fake location.
- 2026-10-11 — **Base 449 nettoyée** (`D:\Temp\opencode\clean449.ipa`, 245.7 MB, SHA256 `4AE2990C036A6F1266B598487E877F2A0D8118DC1E1611EE055DF82EA9D6FBB4`) : fichiers RyukGram supprimés + 4 load commands retirés via LIEF (148 libs, 0 réf. résiduelle, segments valides). Concat des 12 morceaux vérifiée byte-identique.
- 2026-10-11 — **Portage essentiels** : DeviceCheck/App Attest bloqués (`RPHardening`), fake GPS (`RPLocationSpoof`), isolation keychain/app-group/prefs/HOME + IDFV/IDFA (`RPDeviceSpoof`) étaient déjà présents. **Ajout `RPLaunchGuard`** (nouveau) : streak de crashs au lancement, safe mode à 3 (réglages/conteneurs conservés, étapes risquées sautées, alerte « Réactiver ») — branché dans `Bootstrap.m`, entrées L10n `safe.*`, fichier ajouté au `Makefile`. `build.yml` : mode `parts:` ajouté pour la base chunkée.
- 2026-10-09 — Raptor from scratch : Bootstrap, RPPaths/RPContainer/RPContainerStore, RPHomeRedirect/RPKeychainHook/RPPrefsHook/RPAppGroupHook, RPDeviceIdentity (29 modèles, puce stricte), RPDeviceSpoof (IDFV/IDFA/name), RPLocaleSpoof, RPLocationSpoof, RPHardening, RPPermissions, RPCameraFeed/Hook, RPTheme/RPGlass/RPL10n/RPActionSheet/RPFloatingButton/RPListPickerVC/RPMapPickerVC/RPCreateVC/RPPanelVC, RPDiagnostics/RPAppRelaunch, fishhook vendor. Build.yml + Makefile.
