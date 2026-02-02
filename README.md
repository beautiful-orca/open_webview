# Fork of Open WebView - [XDA Thread](https://xdaforums.com/t/magisk-module-webview-open-webview.4496119/)

This module helps you to replace your system webview though Magisk.

## NOTICE
> This is a fork I created for myself. My work is not related to programming or Android developement, so check before installing. It's just a hobby that I do when I have some free time (very little). The original author [F3FFO](https://github.com/F3FFO) is far knowledgeable.

## DISCLAIMER

>I AM NOT RESPONSIBLE IF YOUR DEVICE DOES NOT WORK PROPERLY OR FOR ANY DAMAGE THAT MAY OCCUR TO YOUR DEVICE. BEFORE USING THIS MODULE, PLEASE READ THE CODE. YOU WHO DECIDE TO INSTALL THIS MODULE ASSUMES ALL RESPONSIBILITY FOR ANY PROBLEMS.

## Compatibility (by upstream)

- S.O.:
    - minimum: Android 8+
    - recommended: Android 13+
- Magisk 20.4+
- KernelSU 0.6+

## Tested Device ROM (by upstream)

| API | OS | ROM | version |
|:---:|:--:|:---:|:-------:|
| `26` | `Android 8` |      | `AAPT` |
| `27` | `Android 8.1` |       | `AAPT` |
| `28` | `Android 9` |       | `AAPT` |
| `29` | `Android 10` |       | `AAPT` |
| `30` | `Android 11` |       | `AAPT` |
| `31` | `Android 12` | `LOS 19` | `AAPT` |
| `32` | `Android 12L` | `LOS 19.1` | `AAPT` |
| `33` | `Android 13` | `LOS 20` | `AAPT` |
| `34*` | `Android 14` | `crDroid 10.x`, `LOS 21` | `AAPT2` |
| `35` | `Android 15` |       | `AAPT2` |
| `36` | `Android 16` | `CrDroid 12.5 QPR2, Magisk 30.6`| `AAPT2` |

\* before the security patch update of june 2024 you can still use the AAPT version but if you have a newer version you need to use the AAPT2 version

## Support

You can contribute pull requests or support the original author.

## Features

**ATTENTION!** This module cannot automatically update the webview, so if you want to update a webview installed through this module you must manually reinstall the module.

- Works on any device running Android 8.0+ and Magisk 20.4+
- Replace the webview with one of:
    1. ~~[Bromite](https://github.com/bromite/bromite)~~ (Deprecated, removed)
    2. ~~[Mulch](https://gitlab.com/divested-mobile/mulch)~~ (Deprecated, removed)
    3. [Vanadium](https://gitlab.com/grapheneos/platform_external_vanadium)
    4. ~~[Thorium](https://github.com/Alex313031/Thorium-Android)~~ (Deprecated, removed)
    5. [Cromite](https://github.com/uazo/cromite)

## Create module

1. Clone the repository
2. Run the script according to the OS:
   - Unix/Linux: `./create-module.sh`
   - Windows: `./create-module.ps1`

## Credits

- [Upstream Open Webview by F3FFO](https://github.com/Magisk-Modules-Alt-Repo/open_webview/)
- [Magisk by topjohnwu](https://github.com/topjohnwu/Magisk)
- [MMT-Extended by Zackptg5](https://github.com/Zackptg5/MMT-Extended)
- [Bromite](https://github.com/bromite/bromite)
- [Vanadium by GrapheneOS](https://gitlab.com/grapheneos/platform_external_vanadium)
- [Mulch by DivestOS](https://gitlab.com/divested-mobile/mulch)
- [Thorium by Alex313031](https://github.com/Alex313031/thorium)
- [cUrl](https://github.com/curl/curl)
- [cUrl binary](https://github.com/F3FFO/compile_zlib_openssl_curl_android)
- [Zipsigner by osm0sis](https://github.com/Magisk-Modules-Repo/zipsigner)
- [Cromite by uazo](https://github.com/uazo/cromite)
- [AAPT2 binaries](https://github.com/skittles9823/QuickSwitch)
- [WebViewChanger](https://github.com/Lordify95/WebViewChanger)

## License

Copyright 2024 F3FFO

The source code is available under [GPL-3.0](https://github.com/Magisk-Modules-Alt-Repo/open_fonts/blob/master/LICENSE)

## Change logs

### v2.5.2 (see 2.5.0 changelog for more)

- Prevent post-fs logic if Cromite is choosen as webview

See older release notes: [CHANGELOG.md](CHANGELOG.md)
