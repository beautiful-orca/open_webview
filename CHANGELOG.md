
# v2.6.3 (fork by beautiful-orca)

- README: License section now links this fork's own LICENSE (stale line removed), curl fork attribution clarified in the automation and credits sections [cc98e4f](https://github.com/beautiful-orca/open_webview/commit/cc98e4f3936d167508ffb2a579946419e0d03cd0)
- Vanadium APKs are now also verified against the pinned GrapheneOS signing certificate (`GRAPHENEOS_CERT_SHA256` in `providers.sh`, checked on-device by `apk_signer_cert_sha()` in `common/install.sh` and `action.sh`, fail closed on mismatch). The upstream sha256 is fetched over the same channel as the APK, so it only detects transfer corruption; the certificate pin ships in the module zip and is independent of the download channel, so it detects tampering [8ccb602](https://github.com/beautiful-orca/open_webview/commit/8ccb6025eac69ec046e8002b89b04af0eebfae5b)
- New `vanadium-signing-key.yml` workflow — weekly: full `apksigner verify --v4-signature-file` of every Vanadium prebuilt against its `.idsig`, asserting the signer certificate still equals the pin and the pin still matches the certificate in `overlays/src/`; fails loudly on a key rotation [8ccb602](https://github.com/beautiful-orca/open_webview/commit/8ccb6025eac69ec046e8002b89b04af0eebfae5b)
- Release v2.6.3: version bumped in `module.prop` and `update.json` [0820517](https://github.com/beautiful-orca/open_webview/commit/082051703b259a67e428e8c0effb06b3469560ae)

# v2.6.2 (fork by beautiful-orca)

- Installer ends with a success summary (reboot required, WebView picker in Developer options, action-button updates); `NVBASE` defaults to `/data/adb` on modern Magisk [09c708b](https://github.com/beautiful-orca/open_webview/commit/09c708b109204e6fb3932aecfe1710f69046f202)
- Failed installs/updates copy the log to `/sdcard` (`webview.log` / `action.log`) and point at the issue tracker with the no-guarantee caveat; README documents the after-install flow and log locations [09c708b](https://github.com/beautiful-orca/open_webview/commit/09c708b109204e6fb3932aecfe1710f69046f202)
- Metadata fetches run the DNS ladder with live progress and the big download shows the curl progress meter in the Magisk console; the Vanadium checksum resolves in the background during the download (still fail-closed) [09c708b](https://github.com/beautiful-orca/open_webview/commit/09c708b109204e6fb3932aecfe1710f69046f202)
- Repacked `tools.tar.xz` with literal arch members so the install-time extraction matches; Volume-Key-Selector fallbacks for 64-bit-only devices and missing `getevent`; the action button reads the installed version live via `dumpsys` and backfills the state file [09c708b](https://github.com/beautiful-orca/open_webview/commit/09c708b109204e6fb3932aecfe1710f69046f202)
- Release v2.6.2: version bumped in `module.prop` and `update.json`, module description shortened [16f6aa1](https://github.com/beautiful-orca/open_webview/commit/16f6aa10cdd140c1c95b738e4c5c91d5ef3c3e9e)

# v2.6.1 (fork by beautiful-orca)

- Commit the tool binaries compressed (`common/tools/tools.tar.xz`) instead of raw — repo-size hygiene; the module zip content is unchanged [c95117a](https://github.com/beautiful-orca/open_webview/commit/c95117a823a8bb2042071d9a283e0c0206d56ddd)
- Add the release workflow: builds `open-webview.zip` with `create-module.sh` and publishes it as the release asset on every `v*` tag push [338f462](https://github.com/beautiful-orca/open_webview/commit/338f462b0cd96517ffa57d98b8e9de0372f4ef23)
- Remove the finished execution plan `PLAN.md` [027ff32](https://github.com/beautiful-orca/open_webview/commit/027ff32ea95e22902a9f11cef9b2ed4805140bb1), [f7900cb](https://github.com/beautiful-orca/open_webview/commit/f7900cb56922e83af5bbb7dc1ed2281414ab0e68), [dc3bb32](https://github.com/beautiful-orca/open_webview/commit/dc3bb32e58c873f499f364e28f0039f02054a95b)
- Changelog entry for v2.6.0 [c75f1cd](https://github.com/beautiful-orca/open_webview/commit/c75f1cdfeb1d5aaffa163f0c36e3cc1b238e0436)
- Release v2.6.1 [049b6bc](https://github.com/beautiful-orca/open_webview/commit/049b6bc52f8fe03181d83075276bba7dcca7a3fd)

# v2.6.0 (fork by beautiful-orca)

- Ship a prebuilt, pre-signed `WebviewOverlay.apk` (superset provider list, Vanadium first, `com.android.webview` second) and install it directly instead of building the overlay on-device [15e1dfb](https://github.com/beautiful-orca/open_webview/commit/15e1dfb7a16d51cd9dd9cda1bfabb3f14b972b95), [9b5e1d9](https://github.com/beautiful-orca/open_webview/commit/9b5e1d906fece612fcd7807b41dd2964885cacc2), [a935b06](https://github.com/beautiful-orca/open_webview/commit/a935b065dcf7bb6708dd2904f9490cd6afbe078d), [dee92b9](https://github.com/beautiful-orca/open_webview/commit/dee92b9010840c1e5c8848c65cce875c3905c04a), [0de4423](https://github.com/beautiful-orca/open_webview/commit/0de4423d3ef866e7da29ac302a202daaa82bf68f), [b9f4223](https://github.com/beautiful-orca/open_webview/commit/b9f42236b498607edcbe421efd20c317704c4110)
- Remove the bundled `aapt2` and `zipsigner`; overlay rebuilds move to CI with the pinned SDK build-tools [4a1f927](https://github.com/beautiful-orca/open_webview/commit/4a1f927bb8f8e58345936eeae0e238689230b6a8), [cea0473](https://github.com/beautiful-orca/open_webview/commit/cea0473cdd94e0364f5cae4986b7ba4ff7f04fb0)
- Update the bundled curl to the fork-built release with c-ares (sha256 pinned, monthly CI refresh) [ee7bcbd](https://github.com/beautiful-orca/open_webview/commit/ee7bcbd53d590a4ff6a2cbaa32af52ac3ab2789d), [6c41697](https://github.com/beautiful-orca/open_webview/commit/6c4169708bd5d1b8153cb94faefc53183ea66fc0), [a5ca36b](https://github.com/beautiful-orca/open_webview/commit/a5ca36b6dc1bec46b3894c173e84e4febc331e80)
- Fix broken installs: point providers at the artifacts that actually exist upstream, raise `MINAPI` to 29 [b6fb6b9](https://github.com/beautiful-orca/open_webview/commit/b6fb6b9b4ac4c5d0a655c7c2af50e38d145b6db4), [5788374](https://github.com/beautiful-orca/open_webview/commit/57883747d375963eb069e23ef0f092f8226e6616)
- Remove `post-fs-data.sh`; the one-time migration now runs at install time [1fdc5cf](https://github.com/beautiful-orca/open_webview/commit/1fdc5cfed8e8615f691fafac99cb6d229e49ec44)
- Conflict handling: `.replace` / `pm uninstall` only for the provider's own package, plus `cmd webviewupdate set-webview-implementation` [c584629](https://github.com/beautiful-orca/open_webview/commit/c584629a95eee93a7dbf3f609961052ef979598f)
- Probe the overlay path before the download, including `/vendor/overlay` [8ad6ddc](https://github.com/beautiful-orca/open_webview/commit/8ad6ddc994966de2331f37c8f67c8a4a4dcb2c02)
- Normalise `$ARCH` to the ABI name (`x64` -> `x86_64`) [5f4c11a](https://github.com/beautiful-orca/open_webview/commit/5f4c11aa5b23189870f486f8e8c37dc7b244224b)
- Robust downloads: `CURL_BIN`, `--dns-servers` -> `--doh-url` -> system resolver ladder, real exit-status checks, `unzip -t` gate [6ece78b](https://github.com/beautiful-orca/open_webview/commit/6ece78bc3979cba3a3d91490ac6c919e50bf717f)
- Verify the Vanadium download against the upstream sha256 and fail closed when it cannot be read [24fb03d](https://github.com/beautiful-orca/open_webview/commit/24fb03dba519b7015d4fff8bd00bd3916fd0988a)
- Download to `/data/local/tmp` instead of the `/dev` tmpfs, with a free-space precheck [1082e67](https://github.com/beautiful-orca/open_webview/commit/1082e678212f35a950c5e033bc3be10e90d0b6c8)
- Smoke-test the extracted curl before the first download [1d2145e](https://github.com/beautiful-orca/open_webview/commit/1d2145e068562ab29dcbfe07beadbb28a751ef60)
- Registry-driven one-cycle provider menu with a confirmed default on timeout [6018f86](https://github.com/beautiful-orca/open_webview/commit/6018f86f21c0ff3178b842511885bf42bbfaeded)
- Self-explanatory install log: `say()`, `print_install_summary()`, header read from `module.prop` [86f1e25](https://github.com/beautiful-orca/open_webview/commit/86f1e2552ebe315cb538018179515788b2f7619a)
- Working, idempotent `uninstall.sh` [376890e](https://github.com/beautiful-orca/open_webview/commit/376890ef153d78f69fca413a7fd0812afa7c75c1)
- Always install to `system/app` — the LineageOS branch is gone [8fa2332](https://github.com/beautiful-orca/open_webview/commit/8fa23332081e35cdc827ee426cc4fb42147e567e)
- Extract only the target arch from `tools.tar.xz` [4c4469f](https://github.com/beautiful-orca/open_webview/commit/4c4469f74da68c1271bd87772ab91842aac2ff11)
- Pick the Vanadium arm64 prebuilt variant per device [966a9d8](https://github.com/beautiful-orca/open_webview/commit/966a9d8905527d1ea473f768e29442975f7d80c7)
- Add the `action.sh` update button on top of a shared `providers.sh` registry [a6c6e84](https://github.com/beautiful-orca/open_webview/commit/a6c6e841b5efb189ebea64bc94c917fc8a8779cd), [0148cbe](https://github.com/beautiful-orca/open_webview/commit/0148cbe3ec52015a59eddcb53efac31ecb660712)
- Re-add Thorium as a selectable provider [7b7885d](https://github.com/beautiful-orca/open_webview/commit/7b7885d862a0cdce6392746c6c8e43471a4ffd65)
- Cromite version update [b550309](https://github.com/beautiful-orca/open_webview/commit/b55030972030684eb992ca50206021b474556500)
- CI: weekly watchers for the Vanadium default branch and the SDK package pins, Dependabot for the pinned Actions [22af7f9](https://github.com/beautiful-orca/open_webview/commit/22af7f90cd8a251b424c2507e189731cdc5fe981), [71da2e5](https://github.com/beautiful-orca/open_webview/commit/71da2e54778b6061a7d2dd53085bb016c89731b7), [1af9658](https://github.com/beautiful-orca/open_webview/commit/1af965805665647ecbe85de2d2a98ac7e44c8316), [6d0ac5b](https://github.com/beautiful-orca/open_webview/commit/6d0ac5bc9dad94d67cb339e2982cc0a8db3a1350)
- Docs: README updates with AI-assistance notice, execution plan in `PLAN.md` [f2f6302](https://github.com/beautiful-orca/open_webview/commit/f2f63029695f40c94be11988dd044e4b01598506), [b1db4af](https://github.com/beautiful-orca/open_webview/commit/b1db4af787443be8ff45ca20387f2c888dc5eaf2), [6d82f87](https://github.com/beautiful-orca/open_webview/commit/6d82f870b8357e33123c496019d521f585934a87)
- Release v2.6.0: version bumped in `module.prop` and `update.json` (`v` prefix unified), new release workflow builds and publishes `open-webview.zip` on tag push [573ab05](https://github.com/beautiful-orca/open_webview/commit/573ab0500a740f559d95058005c4fe5e7835a162), [338f462](https://github.com/beautiful-orca/open_webview/commit/338f462b0cd96517ffa57d98b8e9de0372f4ef23), [05666fc](https://github.com/beautiful-orca/open_webview/commit/05666fc45d57472a9f1de0a2ad8bd21fd927b5b4)

# v2.5.5 (fork by beautiful-orca)
- [added notice for old cromite version](https://github.com/beautiful-orca/open_webview/commit/4fd902750ad62cbcbd6f9737bb44eea161a7470e)
- [Updated Vanadium: Branch changed from 16-QPR2 to 17](https://github.com/beautiful-orca/open_webview/commit/5c96a2f6e8a2744f36dbfcd248475a4c4458d46f)
- mention [webview-changer](https://gitlab.com/Lordify/webview-changer) as a better alternative [commit](https://github.com/beautiful-orca/open_webview/commit/11a675aaaa8f16705c9c97684b3c3c3001bc8dfb)


# v2.5.4 (fork by beautiful-orca)

- Tidy up and remove remaining mulch references [791a7e9](https://github.com/beautiful-orca/open_webview/commit/791a7e9001c5f7267a7ad2594c5fb16f8fac3ab9), [b9ea773](https://github.com/beautiful-orca/open_webview/commit/b9ea7732537cc4153506c691af488a29893eaa18), [5709bc7](https://github.com/beautiful-orca/open_webview/commit/5709bc75028824b9a4fc1d283716871bdcd0aba0), [01f5c2f](https://github.com/beautiful-orca/open_webview/commit/01f5c2f3bb883447bf7a242b6052f790dad9eefd), [3bb196a](https://github.com/beautiful-orca/open_webview/commit/3bb196a53457ae2d91ecd7aa4809b315d5e91fbb), 
- update description [67680a3](https://github.com/beautiful-orca/open_webview/commit/67680a39e87b68f640c9799540861de577c6877c), [e54fd0c](https://github.com/beautiful-orca/open_webview/commit/e54fd0c2da17ced02e3d9c237ff699dd93c1c6c8), [37a4a34](https://github.com/beautiful-orca/open_webview/commit/37a4a340dec28281aaddd86cdcba8123215252af)
- fix for vanadium arm64 not booting because of vanadium changes [659a2ac](https://github.com/beautiful-orca/open_webview/commit/659a2ac3d545465b4be3b5e55b68b5a30dd8bf78), see [#3](https://github.com/beautiful-orca/open_webview/issues/3)
- bumb version 2.5.4 [1896c19](https://github.com/beautiful-orca/open_webview/commit/1896c19c538a6f0578d3bba7521d737307edb74a), [4ba280d](https://github.com/beautiful-orca/open_webview/commit/4ba280dee14bc1ed80d4cabd927822322b0f7efc)

# v2.5.3 (fork by beautiful-orca)

- Updated Cromite apk URL [commit](https://github.com/beautiful-orca/open_webview/commit/66da7a3b56d8f89ba1c84ef8bef4f4c8049bf5a5)
- Removed depreceated Mulch option [commit](https://github.com/beautiful-orca/open_webview/commit/9252181a46e87d3da4a44bfbeb6f6462c7001d40)
- Updated Readme
- Fix cromite install [commit](https://github.com/beautiful-orca/open_webview/commit/db57aa2dcd753ce8048c70d796935b94076bf764) [commit](https://github.com/beautiful-orca/open_webview/commit/069f82b373630eda84805e68fd56949cee367f4c)
- [Update Vanadium for Android 16 version 16-qpr2](https://github.com/beautiful-orca/open_webview/commit/7dfdd689e9cef9abf80581047a898bcbca5b92d4)

# v2.5.2

- Prevent post-fs logic if Cromite is choosen as webview

# v2.5.1

- Bug fix

# v2.5.0

- Welcome to Cromite webview
- Bye bye to Thorium webview
- Add support for newest android version
- Add support to Android 15 for Vanadium
- Bug fix

# v2.4.0

- Welcome to Thorium webview
- Mark as **experimental** Vanadium and Thorium
- Add manual installation of Mulch webview
- No need anymore to download thrichrome lib
- Prevent to perform user installation of webview
- Bug fix

# v2.3.1

- KernelSU compatibility. Thanks to @amteza
- Bug fix

# v2.3.0

- Remove Bromite webview
- Re-add overlay inside module
- Add Android 14 support for Vanadium

# v2.2.0

- Add Vanadium webview
- Add SHA256 integrity check for Mulch
- Get always last release of bromite
- Bug fix

# v2.1.0

- Add Mulch webview
- Add status in the module description
- Update bromite to v108.0.5359.156
- Bug fix

# v2.0.0

- Reworked the installation logic
- Add cleaning logic for dalvik cache
- Update bromite to v106.0.5249.163
- Bug fix

# v1.1.0

- Add curl binary
- Bug fix

# v1.0.1

- Bug fix

# v1.0.0

- Initial release
