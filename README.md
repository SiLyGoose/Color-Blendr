# color_blendr

Color Palette Generator

## Release builds

Put Color Blendr's RevenueCat `goog_…` key in `tools/release-config.json`
(copy `tools/release-config.example.json`; it stays out of git), bump
`version:` in `pubspec.yaml`, then run:

- `powershell -File tools\build_aab.ps1`: Play Store bundle, obfuscated, to
  `outputs/aab/ColorBlendr-v<version>.aab`, with debug symbols in
  `outputs/symbols/v<version>/` (keep them).
- `powershell -File tools\build_apk.ps1`: APK for your phone, to
  `outputs/apk/ColorBlendr-v<version>.apk`. Install with `adb install -r` to keep the data.

Details: `docs/monetization.md`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
