# iOS Native Finance Demo

This repository is a small, local-only SwiftUI proof of concept for validating an iOS development and sideloading workflow from Windows 11.

The Windows machine does not compile iOS code. GitHub Actions provisions a GitHub-hosted macOS runner, installs XcodeGen, generates the Xcode project from `project.yml`, compiles an unsigned device build, verifies the embedded widget extension, and uploads `FinanceDemo-unsigned.ipa` as a short-lived artifact.

## Architecture

- `FinanceDemo/App`: SwiftUI app entry point, view, and observable store.
- `FinanceDemo/Models`: shared snapshot model used by the app and widget.
- `FinanceDemo/Services`: App Group storage, Foundation Models, and local notification services.
- `FinanceDemo/Shared`: App Intents and App Shortcuts compiled into both targets.
- `FinanceDemoWidget`: one WidgetKit extension with `systemSmall` and `systemMedium` layouts.
- `FinanceDemo/Config` and `FinanceDemoWidget/Config`: App Group entitlement files and generated Info.plist destinations.
- `.github/workflows/ios-build.yml`: manually triggered unsigned build and IPA packaging workflow.

XcodeGen is used so the project configuration stays declarative and the generated `.xcodeproj` does not need to be committed. CI runs `brew install xcodegen` followed by `xcodegen generate`.

Stable identifiers are intentionally used for every build:

- Main app: `com.josephlteif.financedemo`
- Widget: `com.josephlteif.financedemo.widget`
- App Group: `group.com.josephlteif.financedemo`

The minimum deployment target is iOS 26.0. The demo uses SwiftUI, WidgetKit, AppIntents, UserNotifications, Foundation, and Foundation Models. Foundation Models is entirely on-device; this project does not use OpenAI, Gemini, Claude, Firebase, Supabase, or another backend.

## GitHub Actions build

The workflow runs on the `macos-26` GitHub-hosted runner and prints the macOS, Xcode, and Swift versions used for each build. It is intentionally not triggered for ordinary pushes to `main`.

To build:

1. Open the repository on GitHub.
2. Open **Actions** → **Build unsigned iOS IPA**.
3. Choose **Run workflow** on `main`.
4. Open the completed run and download the `FinanceDemo-unsigned` artifact.

The artifact contains:

- `FinanceDemo-unsigned.ipa`
- `build-info.txt` with the Xcode version, Swift version, commit SHA, and UTC build time.

The IPA is unsigned. Do not use `xcodebuild -exportArchive` for this workflow: exporting requires signing material. CI uses `CODE_SIGNING_ALLOWED=NO` and packages the verified `.app` manually under `Payload/`.

## Windows sideloading setup

The primary route is AltStore Classic through AltServer on Windows. Sideloadly is a secondary fallback. Both use a free Apple ID; a free sideloaded app normally expires after 7 days, so refresh it before expiry. Free accounts also have Apple-imposed limits on simultaneously sideloaded apps and App IDs.

Official installation references:

- AltStore Windows instructions: <https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows>
- Sideloadly: <https://sideloadly.io/>

AltServer and Sideloadly require Apple’s web-installed iTunes and iCloud components on Windows. Microsoft Store iCloud is a known incompatibility for the standard setup. Do not uninstall existing Apple software until you have confirmed which version you want to replace and have a backup plan for any iCloud/iTunes use.

After the software prerequisites are correct, the manual device steps are:

1. Connect the iPhone to the PC by USB while it is unlocked.
2. Tap **Trust** on the iPhone and accept the Windows trust prompt if shown.
3. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone.
4. Run AltServer as administrator and authenticate it with the Apple ID when prompted. Never put the Apple ID password in this repository, GitHub, a script, or chat.
5. Install AltStore to the iPhone. If Wi-Fi refresh is desired, enable Wi-Fi sync for the iPhone in iTunes while it is connected.
6. In AltStore, open the downloaded `FinanceDemo-unsigned.ipa` and let AltStore sign/install it.
7. Trust the developer profile in **Settings → General → VPN & Device Management** if iOS asks for it.
8. Refresh the app from AltStore before the free 7-day signing window expires.

Sideloadly follows the same no-paid-membership principle: load the IPA, select the connected iPhone, authenticate directly in Sideloadly, and sideload. Its official FAQ also documents Wi-Fi pairing and the 7-day free-account window.

## Entitlements and App Groups

Both the main app and the widget declare only this entitlement:

`com.apple.security.application-groups = [group.com.josephlteif.financedemo]`

The app uses `UserDefaults(suiteName: "group.com.josephlteif.financedemo")` and checks the App Group container URL. It never silently falls back to ordinary `UserDefaults`.

The Diagnostics card reports either:

- `Shared App Group: WORKING`
- `Shared App Group: UNAVAILABLE`

When unavailable, the app uses process-local diagnostic state only and labels it as unavailable. OSLog contexts distinguish `main-app`, `widget`, and `app-intent` so device logs can show whether the app, widget, or intent can reach the shared container.

Third-party free signing is the highest-risk part of this proof of concept: it may strip, reject, or fail to preserve App Group capabilities. A successful GitHub build proves compilation and embedding only; it does not prove App Groups work on the physical iPhone.

## Demo acceptance checklist

Complete this on the physical iPhone after installation:

- [ ] Launch the app.
- [ ] Confirm the balance is `$1,000`.
- [ ] Tap **Add $5 Expense** and confirm `$995`.
- [ ] Add the **Demo Balance** widget to the Home Screen and confirm it shows `$995`.
- [ ] Tap the interactive expense button in the widget and confirm the app/widget balance becomes `$990`.
- [ ] Run **Get Demo Balance** from Shortcuts or Siri and confirm it returns the current balance.
- [ ] Tap **Test Notification** and confirm the notification arrives about 10 seconds later.
- [ ] Tap **Test Apple Intelligence** and confirm the availability state and, when available, the generated one-sentence summary.
- [ ] Close and reopen the app; confirm the state persists.
- [ ] Refresh/re-sign the app without deleting it; confirm the state remains.
- [ ] Record whether Diagnostics says `WORKING` or `UNAVAILABLE` after every step.

## Troubleshooting

### GitHub build fails

Open the failed run and inspect the raw `xcodebuild` output. The workflow stops on XcodeGen generation errors, Swift compiler errors, a missing `FinanceDemo.app`, a missing `PlugIns` directory, a missing `.appex`, or a missing IPA.

If Foundation Models symbols change in a newer runner SDK, update `FoundationModelService.swift` against the installed SDK’s compiler errors. The current implementation uses `SystemLanguageModel.default.availability`, handles available, disabled, ineligible, not-ready, and other unavailable states, then creates a local `LanguageModelSession` only when available.

### AltServer cannot see the iPhone

Use the web-installed iTunes and iCloud packages, keep iTunes/iCloud running, connect the unlocked iPhone by USB, tap **Trust**, and run AltServer as administrator. Bonjour is also needed for Wi-Fi discovery. If an existing Microsoft Store Apple package conflicts, resolve that installation choice manually before removing anything.

### App Group says UNAVAILABLE

Reinstall the exact same stable bundle identifiers with the same Apple ID, verify both entitlement files still contain the same App Group, and inspect device logs for the `main-app`, `widget`, and `app-intent` contexts. Do not treat a widget showing a value from its placeholder as proof of shared storage.

### App expires

Free Apple signing is time-limited. Refresh/re-sign from AltStore or Sideloadly before the 7-day window ends. Re-signing should use the same Apple ID and bundle identifiers if you want to preserve the app’s data, but the App Group result must still be verified on the device.

## Security

This repository intentionally contains no Apple password, session token, certificate, provisioning profile, private key, `.p12`, GitHub token, or generated credential file. GitHub Actions performs an unsigned build and never contacts Apple provisioning services.

