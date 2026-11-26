# Bundled tools

## `tools/<arch>/curl`

Built from [`beautiful-orca/curl-android`](https://github.com/beautiful-orca/curl-android)
(branch `master`), a fork of
[`vvb2060/curl-android`](https://github.com/vvb2060/curl-android), with **c-ares**
enabled, so that `--dns-servers` works. The recipe is in `../../CURL-BUILD.md`.

The fork's own workflow publishes per-ABI release assets (`curl-<abi>` + `SHA256SUMS`);
`.github/workflows/update-binaries.yml` in this repo pulls the latest release monthly,
verifies it and opens a PR. The machine-readable record of what is installed is
[`VERSIONS.json`](VERSIONS.json), rewritten by that workflow in the same PR as the
binaries.

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

### Checking a binary

```sh
strings -a common/tools/tools/arm64/curl | grep 'c-ares/%s'      # must match
strings -a common/tools/tools/arm64/curl | grep 'threaded resolve'  # must not match
readelf -dW common/tools/tools/arm64/curl | grep NEEDED          # no libcares.so
```

`c-ares/%s` is the format string curl uses to print the resolver version, so it
is present exactly when c-ares is linked. Do not look for a literal
`c-ares/1.34.9` — the version is filled in at runtime by `ares_version()`.

## `tools/<arch>/aapt2`

Unchanged. From `skittles9823/QuickSwitch`, built with NDK r26c, 4 KB aligned.
Only used at build time if the overlay is compiled on the host; the module ships
a prebuilt overlay APK.

## `zipsigner`, `zipsigner-3.0-dexed.jar`

Unchanged. From `Magisk-Modules-Repo/zipsigner`.
