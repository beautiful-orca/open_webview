# PLAN — open_webview execution order

Derived from `PROJECT-NOTES.md`, which stays the detailed reference: every `§` below
points into it for the diff, the evidence and the verification table. This file is the
concise, prioritized, step-by-step plan. Markdown is excluded from the module zip
(`-x!*.md`), so this file never ships.

## Current state (verified against the tree, 2026-11-26)

Already applied — PROJECT-NOTES is stale about these:

- curl swapped to the fork-built 8.23.0 + c-ares build, sha256 pinned in
  `common/tools/VERSIONS.json`, monthly refresh via `.github/workflows/update-binaries.yml`
  + `scripts/` (§6.5, §8.7 — done; `common/tools/README.md` still shows the 8.18.0
  table, fix the numbers when convenient).
- `aapt2` and `zipsigner` deleted from the repo (commit `4a1f927`).

Broken right now — Phase 1 fixes both:

- Vanadium download: `common/install.sh` still requests `TrichromeWebView.apk` /
  `TrichromeLibrary.apk`, deleted upstream 2026-10-15 → 404 (§2.8 #1).
- Vanadium overlay: `create_overlay` / `sign_framework_res` still call `aapt2` / `sign`,
  which no longer ship → install fails at the overlay step even if the URL were fixed.

Everything else in §8/§9/§12–§16 is not applied.

## Decisions

Carried from PROJECT-NOTES (§10, §12.13, §14.10, §15.11):

- `MINAPI=29` for every provider; no per-provider API gates (§10.4).
- Cromite stays, arm64-only, README keeps the staleness warning (§10.2, §12.11.3).
- x86_64 stays, Vanadium-only there (§10.3).
- `post-fs-data.sh` is removed; the one-time migration runs at install time **in the same
  commit** as the removal (§10.1, §8.4, §9).
- No `service.sh`, no `pm disable`. Conflict handling = overlay list order +
  `cmd webviewupdate set-webview-implementation` + `.replace` / `pm uninstall` only for the
  provider's own package (§14).
- `VanadiumConfig.apk` is not shipped (§10.5).
- Prebuilt, pre-signed overlay APK (AOSP testkey, `versionCode` derived from the XML hash),
  superset provider list, Vanadium first, `com.android.webview` second (§12, §14.3a).
- `extract_lib()` is deleted; libraries load straight from the APK
  (`extractNativeLibs="false"`, 16 KB aligned) (§10.7, §8.1.5).
- LineageOS branch deleted; always `system/app` (§10.8, §8.10).
- No `-k` anywhere; download ladder `--dns-servers` → `--doh-url` → system resolver (§6.5).
- Fail closed when the upstream hash cannot be read (§8.2.1 D2).

New decisions (2026-11-26):

- Work lands as **commits on master — no version bumps, no `update.json` change, no tags
  until release time**. `module.prop`/`update.json` spelling (`v` prefix) is unified at
  release time too (§8.3.2 D7).
- `$ARCH` is normalized to the ABI name in `customize.sh` (`x64` → `x86_64`); the
  `TOOLS_ARCH` workaround in `functions.sh` is removed.
- Thorium as a selectable provider is **deferred to Phase 4** (its overlay entry ships
  anyway and is inert until a provider installs it).
- KernelSU/APatch work — including the ~30-line metamodule detection block — is **fully
  deferred for now**; Magisk only, revisit manually later (§8.9).

## Conventions for all new code

- One `$ARCH` spelling: ABI names (`arm`, `arm64`, `x86`, `x86_64`, `riscv64`).
- `CURL_BIN` variable, not a `curl` alias; per-attempt flags on the download ladder.
- Module id stays `open_webview` (upgrade key).
- Each step is one commit; `sh -n`/`bash -n` on every touched shell file before committing.

---

## Phase 1 — installs work again

One coherent unit: `aapt2` is already deleted, and the post-fs-data removal must ship with
its migration (§10.1). Commit order keeps the tree consistent: overlay source + APK first,
then the installer switch.

1. **Normalize `$ARCH`.** `customize.sh`: `[ "$ARCH" = "x64" ] && ARCH=x86_64` before
   `functions.sh` is sourced. Remove the `TOOLS_ARCH` case in `functions.sh:193-197`, use
   `$ARCH` everywhere. — §8.1.4, defect 22. *Done when:* `sh -n` clean; grep shows no
   `TOOLS_ARCH`.
2. **Overlay source layout.** `git mv overlays/extracted/vanadium-overlay29 overlays/src`;
   extract `testkey.pk8`/`testkey.x509.pem` from the zipsigner jar into `overlays/keys/`
   (jar still in git history if needed); drop `versionCode`/`versionName` from the
   manifest; add `overlays/build.sh`. — §12.5, §12.6, §13.3 steps 1–2, 4.
3. **Overlay XML: superset + order.** Append Aosmium (`org.axpos.aosmium_wv`) and Thorium
   (`com.thorium.webview`) entries, both without `<signature>`; reorder so
   `app.vanadium.webview` is first and `com.android.webview` second. — §12.11, §14.5a,
   §13.3 step 3. *Done when:* 8 `<webviewprovider>` elements, 2 without `<signature>`.
4. **Build and commit `overlays/WebviewOverlay.apk`** with the SDK toolchain
   (`build-tools/36.0.0` aapt2 + apksigner, `android.jar`). — §13.3 step 5.
   *Done when:* `aapt2 dump xmltree` shows 8 providers; `versionCode` = first 7 hex of the
   XML sha256; `apksigner verify --verbose` shows v1+v2, cert `CN=Android`; `resources.arsc`
   stored uncompressed.
5. **Installer switches to the prebuilt overlay.** `common/install.sh`: `OVERLAY_APK_FILE`
   in `vanadium()`/`cromite()`, `create_overlay()` becomes a copy, `sign_framework_res()`
   deleted, `OVERLAY_API` removed, call site guarded on `OVERLAY_APK_FILE`. — §12.8.
6. **Packaging.** `create-module.sh`/`.ps1`: drop the overlay-zip step, exclude
   `overlays/src`, `overlays/keys`, `overlays/build.sh`, fix the quoted-glob `rm`.
   — §12.10. *Done when:* `./create-module.sh` then `7z l open-webview.zip | grep overlays`
   shows only `overlays/WebviewOverlay.apk`.
7. **Provider fixes.** `vanadium()` → `VanadiumWebView.apk`, `VW_TRICHROME_APK_URL=""`;
   `install_webview()` guards `pm install` on the file existing and uses the absolute path;
   `cromite()` aborts on non-arm64, uses `arm64_SystemWebView.apk`,
   `VW_PACKAGE=com.android.webview`. — §8.1.3 parts 1–3, §8.1.1.
8. **`MINAPI=29`** in `customize.sh` and the backstop check in `install.sh` (29 / "10").
   — §8.1, §10.4.
9. **Remove `post-fs-data.sh` + migration, same commit.** Delete the file; add the one-shot
   migration to `customize.sh` (runs late, after download succeeds): delete the old
   `post-fs-data.sh` copy, remove the stale `app.vanadium.WebviewOverlay` entry from
   `/data/system/overlays.xml` (targeted sed, file-exists guarded), remove the old
   `*WebviewOverlay.apk@idmap`, `pm uninstall` the Trichrome libraries, delete `backup/`;
   drop the "Dalvik cache will be cleared" message and the dead `.webview` keys from
   `clean_up()`/`create_config_file()`. — §8.4, §9.1, §9.3, §10.1.
10. **Conflict handling.** Rewrite `replace_old_webview()` for `$VW_PACKAGE` only: if
    `codePath` is under `/data/app/`, `pm uninstall` the update first, re-read `codePath`,
    then `.replace` the system copy. Add `cmd webviewupdate set-webview-implementation
    "$VW_PACKAGE"` after install. — §14.3, §14.5b/c, §8.14 (merged).
11. **`find_overlay_path()` fix.** Probe before the download; add `/vendor/overlay`; fall
    back to `system/overlay/` instead of aborting; remove the dead `$MODPATH/product` block
    in `force_overlay()`. — §8.1.2.
12. **Overlay build workflow.** Add `.github/workflows/overlay.yml`
    (`workflow_dispatch` only, builds with pinned build-tools, opens a PR when the
    compiled XML hash or `versionCode` moved). — §13.6 item 4.

## Phase 2 — robustness and UX

13. **Downloads.** `CURL_BIN` replaces the alias; ladder `--dns-servers` → `--doh-url` →
    plain; `--connect-timeout 15 --max-time 1800 --retry 5 --retry-delay 3
    --retry-connrefused`; test curl's exit status (not `-s`/`-f` on the file); `unzip -t`
    gate; drop `-k` from `download_file`, `get_sha_gitlab`, `get_sha_gitlab_lfs`. — §8.2, §6.5.
14. **Integrity.** `get_sha_gitlab()`: `head -c 4096` + correct `"content_sha256":"` grep;
    wire `VW_SHA` for Vanadium and fail closed if empty; rewrite `check_integrity()`
    (`sha256_of`, 64-hex guard, absolute `$TMPDIR/webview.apk` path). — §8.2.1.
15. **Space/tmpfs.** Delete `extract_lib()` + the `webview.zip` copy (§8.1.5); download to
    `DL_DIR=/data/local/tmp/open_webview` with a `df` precheck and cleanup in `abort()`
    (§8.11).
16. **Menu.** `PROVIDERS` registry + `available_providers()` + one-cycle menu with explicit
    confirmation on timeout; fix the Volume-Key-Selector addon path and make `chooseport`
    three-state with a real deadline and visible countdown. — §8.3.1, defects 10, 21.
17. **Logging.** `say()` helper + `print_install_summary()` before the download; log header
    reads `module.prop` instead of the stale `v2.5.2` literal. — §8.3.2.
18. **`uninstall.sh`.** Fix the leading-dot `find` (or use `pm list packages`/`pm path`);
    idempotent; background subshell after boot with the corrected wait
    (`resetprop -w sys.boot_completed 1`, not `0` — §14.7); best-effort removal of the stale
    `overlays.xml` entry. — §2.6, §2.8 #15/#16, §9.3.
19. **Delete the LineageOS branch**, hardcode `system/app/...` at both call sites. — §8.10.
20. **Arch-only tool extraction.** `tar -xf tools.tar.xz ... "$ARCH/"` (+ `|| clean_up 1`).
    Depends on step 1. — §8.12.
21. **Per-device Vanadium variant.** `vanadium_abi()` picks `arm64` vs `arm64-multilib` from
    `ro.product.cpu.abilist` (empty → multilib). After step 15. — §8.13.
22. **curl smoke test.** `curl --version` in `customize.sh` after extraction, abort with a
    clear message on failure. — §6.5/§8.7 leftover.

## Phase 3 — update button (`action.sh`)

23. **`providers.sh`** at module root: registry, `provider_url`/`provider_sha`,
    `cromite_latest` (one `releases/latest` call returning tag + asset digest, replacing
    `get_version_github`), shared `dl`/`sha256_of`/`get_sha_gitlab`; sourced by both
    `common/install.sh` and `action.sh`. — §15.7f, §8.2 item 4.
24. **`action.sh`** + supporting changes: copy the target arch's curl to `$MODPATH/bin/curl`
    before `cleanup()` removes `common/`; `set_perm` it in `customize.sh`; write the four
    state keys (`VW_PROVIDER`, `VW_VARIANT`, `VW_SHA_INSTALLED`, `VW_VERSION`) to `.webview`;
    `uninstall.sh` gains `pm uninstall "$VW_PACKAGE"` (no `--user`) in the post-boot
    subshell. — §15.5–§15.7.
    *Done when:* the §15.9 verification gates pass (up-to-date second tap, hash mismatch
    aborts, offline aborts, `bin/curl` survives install, `common/` is gone).

## Phase 4 — extras

25. **Thorium provider.** One registry row (`thorium|Thorium|29|arm64:SystemWebView_arm64.apk
    arm:SystemWebView_arm32.apk`) + one `thorium()` function; overlay entry already ships.
    Add to `uninstall.sh` package list and README. — §8.6, issue #5.
26. **Vanadium branch watcher.** `.github/workflows/vanadium-branch.yml` — unblocked once
    step 7 lands (Gate B checks every URL `install.sh` builds). Also fix the stale
    `16-qpr2` comment above `ANDROID_VANADIUM_VERSION` and §6.1's branch list. — §16.

## Deferred (do not start unless re-decided)

- Full KernelSU/APatch compatibility incl. the metamodule detection block and the
  `.replace`-under-overlayfs question (§8.9). Magisk only for now.
- Version bumps, `update.json`, `v`-prefix unification, git tags — at release time.
- `VanadiumConfig.apk` (§10.5), `service.sh` (§3.3e), `pm disable` (§14.6), per-arch
  `curl.zip` packaging (§4.3f), repo-size compression of binaries (§4.3f).

## Release gate (run before tagging any release)

The §9.4 test matrix: fresh Vanadium arm64, fresh Cromite arm64, upgrade from v2.5.5
(Vanadium and Cromite), failed-download upgrade leaves the old module working, disable →
stock WebView back, uninstall → stock back + `/data/app` clean + `overlays.xml` clean,
no-network → clear abort with log path. Device-only rows cannot be skipped.
