# Fork of Open WebView - [XDA Thread](https://xdaforums.com/t/magisk-module-webview-open-webview.4496119/)

This module replaces your system WebView systemlessly. On install, pick a WebView implementation (Vanadium, Thorium, or Cromite) from the menu; use the action button to update the installed WebView without re-flashing.

> [!NOTE]
> 26/11: Cromite is currently not updated fast enough (last release: Sep 15 2026, v153.0.8010.37 — an old Chromium version may be a security risk).  
> Vanadium and Thorium are the up-to-date options: the module tracks their current upstream branch/release, and the action button updates the installed WebView without re-flashing.  
> **Attention:** the module is now developed with the help of AI — read and verify the code yourself before installing.

## NOTICE
> This is a fork I created for myself. I don't work in programming or Android development, so check the code before installing.
>
> Recent changes are AI-assisted. Don't trust them blindly — read and verify the code yourself before installing.

## DISCLAIMER

>I AM NOT RESPONSIBLE IF YOUR DEVICE DOES NOT WORK PROPERLY OR FOR ANY DAMAGE THAT MAY OCCUR TO YOUR DEVICE. BEFORE USING THIS MODULE, PLEASE READ THE CODE. YOU WHO DECIDE TO INSTALL THIS MODULE ASSUMES ALL RESPONSIBILITY FOR ANY PROBLEMS.

## Compatibility

- S.O.:
    - minimum: Android 10+ (API 29, every provider is a Chromium fork)
    - recommended: Android 13+
- Root manager:
    - Magisk 20.4+
    - KernelSU 0.6+
- Architectures (per provider, see the registry in `providers.sh`):
    - `arm64`: Vanadium, Thorium, Cromite
    - `arm` (32-bit): Thorium
    - `x86_64`: Vanadium

## Support

You can contribute pull requests or support the original author.

## Features

- Works on any device running Android 10+ (API 29+) and Magisk 20.4+ / KernelSU 0.6+
- At install, a volume-key menu lists the providers your device can run (the registry
  in `providers.sh` decides what is offered: provider + minimum API + architectures)
- Replace the webview with one of:
    1. ~~[Bromite](https://github.com/bromite/bromite)~~ (Deprecated, removed)
    2. ~~[Mulch](https://gitlab.com/divested-mobile/mulch)~~ (Deprecated, removed)
    3. [Vanadium](https://gitlab.com/grapheneos/platform_external_vanadium) (arm64 and x86_64; frequent Chromium updates — on arm64 the smaller `arm64` or the `arm64-multilib` prebuilt is picked per device)
    4. [Thorium](https://github.com/gz83/thorium) — a contributor fork of [Alex313031/thorium](https://github.com/Alex313031/thorium) that publishes the Android builds (arm64 and arm32 only; current Chromium)
    5. [Cromite](https://github.com/uazo/cromite) (arm64 only; last update: Sep 15 2026, v153.0.8010.37, old chromium version may be a security risk)
- Every download is verified against the upstream sha256 (GitLab `content_sha256` for
  Vanadium, release asset digests for Cromite/Thorium), and the install **fails closed**
  when the hash cannot be read — an unverified WebView is never installed. Downloads
  use retries and timeouts plus a DNS fallback ladder (direct resolver → DoH → system
  resolver), with TLS certificate verification on
- Ships a prebuilt, pre-signed overlay APK (`overlays/WebviewOverlay.apk`) that
  registers the non-stock WebView packages (Vanadium, Thorium — Cromite reuses the
  stock `com.android.webview` package name and needs no overlay). No on-device build
  tools (`aapt2`, `zipsigner`) are needed at install time anymore
- The module's action button in the Magisk app updates the installed webview to the
  current upstream build of the same provider — no re-flash, no reboot. It compares the
  upstream and installed sha256, reports "already up to date" when nothing moved, and
  leaves the current WebView untouched on any failure (log: `action.log` in the module
  dir). To switch to a different provider, reinstall the module and pick it in the menu
- No boot-time scripts: `post-fs-data.sh` is gone (the overlay is a static RRO, enabled
  at boot on its own). The one-time migration of old installs runs at install time, and
  `uninstall.sh` restores the stock WebView

## After install

The installer ends with a summary instead of a bare "Done":

- **Restart the device** — the new WebView only takes effect after a reboot.
- The WebView implementation can be chosen in the **Developer options** of Android.
- The WebView can be **updated later with the module's action button** in the Magisk app.

Logs and error reports:

- The install log is kept at `webview.log` in the module dir (`/data/adb/modules/open_webview/`).
  When an install fails, it is copied to **`/sdcard/webview.log`**.
- The update button logs to `action.log` in the module dir; when an update fails, it is
  copied to **`/sdcard/action.log`**.
- To report an error, open an issue on GitHub and include the log:
  <https://github.com/beautiful-orca/open_webview/issues>
  There is no guarantee that a reported issue can be fixed.

## Create module

1. Clone the repository
2. Run the script according to the OS:
   - Unix/Linux: `./create-module.sh`
   - Windows: `./create-module.ps1`

The module zip ships the prebuilt `overlays/WebviewOverlay.apk`. To rebuild it after
changing `overlays/src/`, run `overlays/build.sh` with the Android SDK on `PATH`
(build-tools + platform) — or just push: the `overlay` GitHub workflow rebuilds it,
verifies the compiled result and opens a PR.

## Automation (keeps the module current)

- `update-binaries.yml` — monthly: pulls the newest release of the curl binary of [beautiful-orca curl-android fork](https://github.com/beautiful-orca/curl-android), verifies
  the sha256 pins and opens a PR; what ships is recorded in `common/tools/VERSIONS.json`
- `vanadium-branch.yml` — weekly: opens a PR when Vanadium's default branch moves
  (`ANDROID_VANADIUM_VERSION` in `providers.sh`)
- `overlay.yml` — rebuilds `WebviewOverlay.apk` from `overlays/src/` when it changes
- `sdk-packages.yml` — weekly: watches the Android SDK build-tools/platform pins used
  by the overlay build
- Dependabot bumps the pinned GitHub Actions; a guard workflow auto-merges only those PRs

## Credits

- [Upstream Open Webview by F3FFO](https://github.com/Magisk-Modules-Alt-Repo/open_webview/)
- [Magisk by topjohnwu](https://github.com/topjohnwu/Magisk)
- [MMT-Extended by Zackptg5](https://github.com/Zackptg5/MMT-Extended)
- [Bromite](https://github.com/bromite/bromite)
- [Vanadium by GrapheneOS](https://gitlab.com/grapheneos/platform_external_vanadium)
- [Mulch by DivestOS](https://gitlab.com/divested-mobile/mulch)
- [Thorium by Alex313031](https://github.com/Alex313031/thorium) (Android builds from [gz83/thorium](https://github.com/gz83/thorium))
- [cUrl](https://github.com/curl/curl)
- [curl binary](https://github.com/beautiful-orca/curl-android) — beautiful-orca fork of [vvb2060/curl-android](https://github.com/vvb2060/curl-android), built with c-ares so `--dns-servers` works; refreshed monthly by CI and pinned in `common/tools/VERSIONS.json`
- [Cromite by uazo](https://github.com/uazo/cromite)
- [WebViewChanger](https://github.com/Lordify95/WebViewChanger)
- [Vanadium-WebViewBrowser by NoneBaiano](https://github.com/NoneBaiano/Vanadium-WebViewBrowser) (fork of WebViewChanger; download-with-retries and uninstall patterns)

## License

The source code is available under [GPL-3.0](https://github.com/beautiful-orca/open_webview/blob/master/LICENSE)

## Change logs

See: [CHANGELOG.md](CHANGELOG.md)
