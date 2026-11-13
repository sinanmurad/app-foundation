# Contributing

Thanks for helping! This repo is a template, so the goal is **small, general, and always compiling**.

## Rules of thumb
- Only add things almost every app needs (auth, payments, AI, search, sharing, CI). App-specific code does not belong here.
- Before opening a PR run:
  ```bash
  dart tool/preflight.dart
  flutter analyze
  ```
  CI runs both plus an Android debug build.
- New UI text: add the key to **all 4** ARB files (`lib/l10n/`), then use `AppLocalizations`.
- Never commit `.env`, keystores or `*.p8` files.

## Good first contributions
- Flutter/Gradle/AGP compatibility fixes (new releases break things often).
- Docs and setup-checklist improvements.
- Replacing deprecated APIs reported by `flutter analyze`.
- Screenshots / demo GIFs.

## Reporting a problem
Use the issue templates. Include your Flutter version (`flutter --version`) and the full error output.
