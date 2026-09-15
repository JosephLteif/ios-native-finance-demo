# Pocket Ledger

Pocket Ledger is a small, local-only SwiftUI proof of concept for validating an iOS development and sideloading workflow from Windows 11 while shaping a personal finance product for Lebanon. It is intentionally an MVP validation app, not a production finance product.

The public app name is **Pocket Ledger**. The internal Xcode target, source directory, bundle IDs, and IPA filename remain **FinanceDemo** so free-Apple-ID testing keeps stable identifiers between builds.

The Windows machine does not compile iOS code. GitHub Actions provisions a GitHub-hosted macOS runner, installs XcodeGen, generates the Xcode project from `project.yml`, compiles an unsigned device build, verifies the embedded widget extension, and uploads `FinanceDemo-unsigned.ipa` as a short-lived artifact.

## Architecture

- `FinanceDemo/App`: SwiftUI app entry point, ledger store, finance views, and the app-only Siri/Shortcuts provider.
- `FinanceDemo/Models`: shared snapshot model plus the multi-currency finance domain model.
- `FinanceDemo/Services`: App Group storage, finance data storage, Foundation Models, and local notification services.
- `FinanceDemo/Shared`: App Intents shared by the main app and widget for finance-ledger actions.
- `FinanceDemoWidget`: one WidgetKit extension with `systemSmall` and `systemMedium` layouts.
- `FinanceDemo/Config` and `FinanceDemoWidget/Config`: App Group entitlement files and generated Info.plist destinations.
- `FinanceDemo/Resources/Assets.xcassets`: the Pocket Ledger app icon.
- `.github/workflows/ios-build.yml`: manually triggered unsigned build and IPA packaging workflow.

XcodeGen is used so the project configuration stays declarative and the generated `.xcodeproj` does not need to be committed. CI runs `brew install xcodegen` followed by `xcodegen generate`.

## Finance product slice

The main app now contains the first local finance workflow for the Lebanese market:

- USD and LBP are stored as integer minor units, so LBP values do not use floating-point rounding.
- A single transaction can record a bill total, multiple outflows from different accounts, multiple inflows, and a custom exchange rate.
- Change can be returned to a different account and currency. Requested change and actual change are both retained, so denomination shortfalls such as 460,000 LBP requested and 450,000 LBP returned remain visible.
- Starter data includes cash, bank-account, and loan account types plus parent categories and subcategories. Accounts and categories can be added from the app.
- The Overview tab reports available balances by currency, monthly expenses by currency, transaction count, and the most-used category.
- The widget and Shortcuts read and mutate the same shared finance ledger as the main app.

The current slice is local-only and intentionally keeps currency totals separate. It records the exchange rate for each mixed-currency transaction but does not yet convert all historical balances into one net-worth number.

Stable identifiers are intentionally used for every build:

- Main app: `com.josephlteif.financedemo`
- Widget: `com.josephlteif.financedemo.widget`
- App Group: `group.com.josephlteif.financedemo`

The minimum deployment target is iOS 26.0. The demo uses SwiftUI, WidgetKit, AppIntents, UserNotifications, Foundation, and Foundation Models. Foundation Models is entirely on-device; this project does not use OpenAI, Gemini, Claude, Firebase, Supabase, or another backend.

## Branding

![Pocket Ledger app icon](FinanceDemo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)

Pocket Ledger uses a dark navy, teal, emerald, and warm gold wallet/ledger mark. The source icon is stored at `FinanceDemo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` and is included in the main app target through XcodeGen. The internal `FinanceDemo` names are deliberate implementation details and should not be renamed during free-signing tests.

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

AltStore’s Windows instructions require the latest iTunes and iCloud packages downloaded directly from Apple rather than the Microsoft Store versions for the standard setup. Sideloadly documents the same web-installed iTunes/iCloud requirement. Do not uninstall existing Apple software automatically: first identify whether the installed package is the Microsoft Store version, and decide which Apple software you want to keep.

AltStore installation and IPA installation are separate steps. First install AltStore itself through AltServer; only after AltStore is working should you import the unsigned Pocket Ledger IPA.

After the software prerequisites are correct, the manual device steps are:

1. Install AltServer from the official AltStore Windows download and run it as administrator.
2. Connect the iPhone to the PC by USB while it is unlocked.
3. Tap **Trust** on the iPhone and accept the Windows trust prompt if shown.
4. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone, then restart if iOS requests it.
5. Open iTunes and enable Wi-Fi sync for the iPhone if Wi-Fi refresh is desired.
6. Use AltServer’s **Install AltStore** menu to install AltStore itself, then authenticate directly in AltServer with the Apple ID. Never put the Apple ID password in this repository, GitHub, a script, or chat.
7. Trust the developer profile in **Settings → General → VPN & Device Management** if iOS asks for it.
8. Download the completed `FinanceDemo-unsigned.ipa` artifact from GitHub Actions.
9. Open/share the IPA into AltStore and let AltStore sign/install Pocket Ledger.
10. Refresh the app from AltStore before the free 7-day signing window expires.

Sideloadly follows the same no-paid-membership principle: load the IPA, select the connected iPhone, authenticate directly in Sideloadly, and sideload. Its official FAQ also documents Wi-Fi pairing and the 7-day free-account window.

## Entitlements and App Groups

Both the main app and the widget declare only this entitlement:

`com.apple.security.application-groups = [group.com.josephlteif.financedemo]`

The app uses `UserDefaults(suiteName: "group.com.josephlteif.financedemo")` only when the App Group is authorized. It does not silently fall back to ordinary `UserDefaults`: if the shared container is unavailable, the UI reports that state and keeps only in-memory diagnostic values. This prevents a working-looking main app from masking a failed App Group test.

The Diagnostics card reports either:

- `Shared App Group: WORKING`
- `Shared App Group: UNAVAILABLE`

When unavailable, the app labels the widget's shared container as unavailable and reports main-app storage as unavailable. OSLog contexts distinguish `main-app`, `widget`, and `app-intent` so device logs can show which process can reach the shared container.

Third-party free signing is the highest-risk part of this proof of concept: it may strip, reject, or fail to preserve App Group capabilities. A successful GitHub build proves compilation and embedding only; it does not prove App Groups work on the physical iPhone.

## Finance acceptance checklist

Complete this on the physical iPhone after installation:

- [ ] Launch the app.
- [ ] Confirm the Overview tab shows separate USD and LBP balances.
- [ ] Add an expense with a `$10` bill total, `$9 paid from a USD cash account, and `90,000 LBP` paid from an LBP cash account.
- [ ] Add `450,000 LBP` returned to an LBP account, enter `460,000 LBP` as requested change, and confirm the transaction shows the denomination shortfall.
- [ ] Reopen the app and confirm the transaction and account balances persist.
- [ ] Add a bank account, loan account, top-level category, and subcategory.
- [ ] Add the Pocket Ledger widget and confirm it shows separate USD and LBP balances.
- [ ] Use the widget quick action or the Pocket Ledger expense Shortcut and confirm the new expense appears in Transactions.
- [ ] Run the balance Shortcut and confirm it returns both USD and LBP balances.
- [ ] Refresh/re-sign the app without deleting it; confirm the state remains.
- [ ] Record whether shared App Group storage is `WORKING` or `UNAVAILABLE` during device validation.

## Troubleshooting

### GitHub build fails

Open the failed run and inspect the raw `xcodebuild` output. The workflow stops on XcodeGen generation errors, Swift compiler errors, a missing `FinanceDemo.app`, a missing `PlugIns` directory, a missing `.appex`, or a missing IPA.

If Foundation Models symbols change in a newer runner SDK, update `FoundationModelService.swift` against the installed SDK’s compiler errors. The current implementation uses `SystemLanguageModel.default.availability`, handles available, disabled, ineligible, not-ready, and other unavailable states, then creates a local `LanguageModelSession` only when available.

### AltServer cannot see the iPhone

Use the web-installed iTunes and iCloud packages, keep iTunes/iCloud running, connect the unlocked iPhone by USB, tap **Trust**, and run AltServer as administrator. Bonjour is also needed for Wi-Fi discovery. If an existing Microsoft Store Apple package conflicts, resolve that installation choice manually before removing anything.

### App Group says UNAVAILABLE

Reinstall the exact same stable bundle identifiers with the same Apple ID, verify both entitlement files still contain the same App Group, and inspect device logs for the `main-app`, `widget`, and `app-intent` contexts. Do not treat a widget showing a value from its placeholder as proof of shared storage. Free third-party signing may strip, reject, or fail to preserve App Groups; only the physical-device checklist can validate this path.

### App expires

Free Apple signing is time-limited. Refresh/re-sign from AltStore or Sideloadly before the 7-day window ends. Re-signing should use the same Apple ID and bundle identifiers if you want to preserve the app’s data, but the App Group result must still be verified on the device.

## Security

This repository intentionally contains no Apple password, session token, certificate, provisioning profile, private key, `.p12`, GitHub token, or generated credential file. GitHub Actions performs an unsigned build and never contacts Apple provisioning services.
