# Pocket Ledger

Pocket Ledger is a local-first personal finance ledger for iPhone and Apple Watch, built with SwiftUI. Record multi-currency accounts, transactions, budgets, receipts, and reports without linking a bank account.

[Public site](https://josephlteif.github.io/pocket-ledger/) · [Privacy policy](https://josephlteif.github.io/pocket-ledger/privacy/) · [Support](https://josephlteif.github.io/pocket-ledger/support/) · [Source](https://github.com/JosephLteif/pocket-ledger)

## What it does

- Tracks account balances separately by currency, including USD and LBP.
- Records purchases split across accounts, transfers, exchange rates, and change returned in another currency.
- Supports searchable and editable transaction history, budgets, scheduled entries, templates, and reporting.
- Imports CSV, TSV, JSON, Excel, and supported SQLite exports. Full `.pocketledger` backups can include receipt attachments.
- Scans receipts on device and offers optional on-device writing assistance when Apple’s Foundation Models are available.
- Includes widgets, Apple Watch views, and authenticated Siri, Shortcuts, and system control actions.

## Privacy and data

Ledger data and attachments are stored locally on the user’s devices. The app does not connect to financial institutions or send ledger data to a developer-operated server, advertising network, analytics service, or third-party AI service. Watch features can synchronize selected data to a paired Apple Watch. Exports are shared only when the user chooses a destination.

Read the full [privacy policy](https://josephlteif.github.io/pocket-ledger/privacy/). For support, use the [support page](https://josephlteif.github.io/pocket-ledger/support/); public issue reports must not include private financial information.

## Platforms

The current project configuration targets iOS 26 and watchOS 26. The app is native SwiftUI and includes a WidgetKit extension and Apple Watch companion. Internal target and source names remain `FinanceDemo` for compatibility with the existing build and signing workflow.

## Build an unsigned iOS artifact

The repository’s **Build unsigned iOS IPA** GitHub Actions workflow uses a macOS runner and XcodeGen to create the Xcode project from `project.yml`. It builds without Apple signing credentials and uploads a short-lived artifact. The workflow can also build the Watch app and optionally run Simulator tests.

1. Open the repository’s **Actions** tab.
2. Select **Build unsigned iOS IPA** and choose **Run workflow**.
3. Download the artifact from the completed run.

The unsigned artifact is for development and sideloading; it is not an App Store distribution build. This checkout can’t compile iOS code locally on Windows. Apple signing, App Store metadata, and on-device behavior require separate Apple-side setup and review.

## Project layout

- `FinanceDemo/App`: SwiftUI screens, ledger state, import/export, and app intents.
- `FinanceDemo/Models`: ledger, finance, and reporting models.
- `FinanceDemo/Services`: storage, security, receipt processing, Watch connectivity, and local notifications.
- `FinanceDemo/Shared`: shared intents and Watch data contracts.
- `FinanceDemoWidget`, `FinanceDemoWatch`, `FinanceDemoWatchWidget`: widgets and Watch targets.
- `FinanceDemo/Config` and extension `Config` folders: entitlements and privacy manifests.
- `docs/`: public product, privacy, and support pages deployed with GitHub Pages.
- `.github/workflows/`: unsigned app build and public site deployment workflows.

## Security notes

The optional app lock protects the main app surface. Widgets and other system surfaces are separate from that lock; review their privacy settings on your devices if balances should remain hidden. File imports, exports, and backups are user initiated. See the in-app privacy policy and the public [privacy page](https://josephlteif.github.io/pocket-ledger/privacy/) for storage and deletion details.

## Support

Report reproducible issues through [GitHub Issues](https://github.com/JosephLteif/pocket-ledger/issues). Keep reports general: never attach account or transaction details, receipts, backups, passwords, or other private information to a public issue.
