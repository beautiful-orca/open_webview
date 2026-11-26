# Bundled tools

## `tools/<arch>/curl`

Built from [`beautiful-orca/curl-android`](https://github.com/beautiful-orca/curl-android)
(branch `master`), a fork of
[`vvb2060/curl-android`](https://github.com/vvb2060/curl-android), with **c-ares**
enabled, so that `--dns-servers` works. What is pulled and how it is built is recorded
below.

The fork's own workflow publishes per-ABI release assets (`curl-<abi>` + `SHA256SUMS`);
`.github/workflows/update-binaries.yml` in this repo pulls the latest release monthly,
verifies it and opens a PR. The machine-readable record of what is installed is
[`VERSIONS.json`](VERSIONS.json), rewritten by that workflow in the same PR as the
binaries.

### The refresh pipeline

`build-curl.yml` in the fork (daily + `workflow_dispatch`) publishes the `curl-<abi>`
assets and `SHA256SUMS`. `update-binaries.yml` in this repo (monthly + `workflow_dispatch`)
downloads them, gates on `scripts/verify-binaries.sh`, installs with
`scripts/install-binaries.sh`, rewrites [`VERSIONS.json`](VERSIONS.json) with
`scripts/update-manifest.sh`, and opens a PR. Caveats: cron is UTC and best-effort and a
scheduled run only fires from the default branch; scheduled workflows in public repos
switch off after 60 days without repository activity (keep `workflow_dispatch`); a PR
opened with `GITHUB_TOKEN` does not trigger other workflows — use a PAT if it should.

| | |
|---|---|
| fork | `beautiful-orca/curl-android` @ `master` (releases: `v<curl-version>`) |
| upstream base | `vvb2060/curl-android` @ `b5b06a1` ("fix build", 2026-01-14) |
| curl | 8.18.0-DEV (submodule `curl/curl` @ `2eebc58`, tag `curl-8_18_0`) |
| c-ares | 1.34.9 (submodule `c-ares/c-ares` @ tag `v1.34.9`) |
| resolver | c-ares (`--dns-servers` works; threaded resolver not compiled) |
| NDK | 29.0.14206865 (r29) |
| build | `./gradlew :tool:assembleRelease`, 2026-11-25 |
| linking | dynamic: `libz.so libc.so libm.so libdl.so` (all platform libraries) |
| LOAD alignment | 16 KB (`0x4000`) on arm64-v8a and x86_64, 4 KB on the 32-bit ABIs |

`lib/<abi>/libcurl.so` from the tool APK, renamed to `curl`:

| arch | ABI | bytes | sha256 |
|---|---|---|---|
| `arm64` | arm64-v8a | 3,060,856 | `69230472854e84e1cf6ddba4cbf0de5b560c3c118bbe3aab894dc35d025e406d` |
| `arm` | armeabi-v7a | 1,463,540 | `a44e7e47af563700a653425f33bd9803dcfc1cca6bd3bf8213026667b2221f69` |
| `x86` | x86 | 3,233,880 | `5b0e650159e18bce3b16ded08fdf137a8e9e7edea288bfe52189c684e1383623` |
| `x86_64` | x86_64 | 3,412,920 | `a254b61a78583ed626717d5cb3a15b8480dbd436640136fee59e015d6bc185cb` |

Total 11,171,196 bytes for the four ABIs, against 29,077,040 for the previous
8.3.0-DEV static binaries.

The previous binaries came from the archived
`Zackptg5/Cross-Compiled-Binaries-Android` (curl 8.3.0-DEV, statically linked,
4 KB aligned on every ABI, so they cannot load on 16 KB page-size devices).

### How it is built

The full recipe lives in the fork as scripts and CI (branch `c-ares`), not as a doc in
this repo. In order:

1. `scripts/prepare-sources.sh` materialises the generated version headers the
   submodules do not carry — without it `ndk-build` fails on a missing `nghttp2ver.h`.
2. `scripts/build-cares.sh` builds a static `libcares.a` per ABI with c-ares' own CMake
   (all five ABIs including riscv64, because `ndk-build` configures every one).
3. `scripts/patch-config.sh` sets `USE_ARES 1` and undefines `USE_THREADS_POSIX` in
   `config32/` and `config64/curl_config.h` — both defined is a compile error, and
   upstream regenerates these files on a curl bump, so the script fails loudly if the
   lines move.
4. `Android.mk` adds a `cares_static` prebuilt module and links it into `curl_static`.
5. `./gradlew :tool:assembleRelease`, then extract `lib/<abi>/libcurl.so` from the tool
   APK into `out/<abi>/` — never `unzip -j` across ABIs, the files overwrite each other.
6. Install as `tools/<arch>/curl` (`arm64-v8a`→`arm64`, `armeabi-v7a`→`arm`, `x86`→`x86`,
   `x86_64`→`x86_64`; riscv64 is not shipped) and record the sha256 in the table above.

`.github/workflows/build-curl.yml` in the fork runs this daily, gates on
`scripts/verify-curl.sh` — `c-ares/%s` present, no `threaded resolve`, NEEDED limited to
`libz libc libm libdl` — and publishes the release that `update-binaries.yml` in this
repo pulls.

### Checking a binary

```sh
strings -a common/tools/tools/arm64/curl | grep 'c-ares/%s'      # must match
strings -a common/tools/tools/arm64/curl | grep 'threaded resolve'  # must not match
readelf -dW common/tools/tools/arm64/curl | grep NEEDED          # no libcares.so
```

`c-ares/%s` is the format string curl uses to print the resolver version, so it
is present exactly when c-ares is linked. Do not look for a literal
`c-ares/1.34.9` — the version is filled in at runtime by `ares_version()`.
