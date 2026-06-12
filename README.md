# NekoSim

NekoSim is a cross-platform SIM & eSIM asset management app. It builds on the eSIM management core of [NekokoLPA2](https://github.com/iebb/NekokoLPA2) and adds a full asset layer on top: track every physical SIM and eSIM you own — where it came from, what it costs, when it expires — and link those records to the actual profiles on your cards.

## What NekoSim adds

- **SIM asset library**: Record carriers, plans, costs, validity periods, and notes for every SIM/eSIM you own, with full CRUD management
- **Profile linking**: Two-way association between asset records and the eSIM profiles detected on your cards
- **Expiry reminders**: Local scheduled notifications, plus optional cloud reminders via a self-hostable SimJiang-protocol server
- **Import & export**: Back up and restore your asset library
- **Search, filter, sort**: Find assets quickly across carriers, tags, and validity status
- **Flexible LPA import**: Add profiles by QR scan, image recognition, or pasted activation codes
- **9 languages**: English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Español, Français, Italiano
- **Unified glass UI**: A consistent glassmorphism design across asset pages and eSIM management chrome

## eSIM management core

Inherited from the NekokoLPA2 core, NekoSim works with local eUICCs, external readers, and remote reader endpoints:

| Connection Type | Android | iOS | macOS | Linux | Windows | Chrome |
| --- | --- | --- | --- | --- | --- | --- |
| BLE readers | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| USB CCID readers | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Remote readers | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| OMAPI | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Telephony / TMAPI | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `OTBridge` provider | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| WebUSB SCRP / WebCard | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

Notes:
- `Telephony / TMAPI` and `OTBridge` are Android-only paths.
- On rooted Android devices, [OTBridge](https://github.com/iebb/OTBridge/releases) can enable Telephony support and help bypass OMAPI ARA-M restrictions while keeping NekoSim itself on the normal app path.
- Chrome support refers to the web build running in a Chromium browser with the required browser APIs available.

NekoSim's asset management layer is currently developed and tested primarily on Android.

## Download

NekoSim is under active development toward its first public release. Builds will be published on the [Releases](https://github.com/lincheuk/nekosim/releases) page.

## Building from source

```sh
flutter pub get
flutter build apk --release --flavor community --split-per-abi
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Support

For issues, feature requests, or questions, please use [GitHub Issues](https://github.com/lincheuk/nekosim/issues).

## Credits, trademarks, and license

NekoSim is an independent fork of [NekokoLPA2](https://github.com/iebb/NekokoLPA2) by Nekoko. It is not affiliated with, authorized, certified, or endorsed by NekokoLPA or SIMLINK LTD. **NekokoLPA is a registered trademark of SIMLINK LTD**; the name is used here only to truthfully describe this project's origin and compatibility. The NekokoLPA cat mascot artwork (by @sanzennami) is not used as NekoSim's logo or branding. See [NOTICE](NOTICE) and [BRANDING.md](BRANDING.md) for details.

NekoSim is released under the [MIT License](LICENSE), preserving the upstream copyright.
