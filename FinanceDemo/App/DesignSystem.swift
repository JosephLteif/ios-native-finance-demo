import SwiftUI

enum PocketLedgerTheme {
    static let background = Color(red: 0.04, green: 0.08, blue: 0.13)
    static let surface = Color(red: 0.07, green: 0.13, blue: 0.20)
    static let surfaceElevated = Color(red: 0.10, green: 0.19, blue: 0.28)
    static let divider = Color.white.opacity(0.11)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.70)
    static let income = Color(red: 0.37, green: 0.66, blue: 1.00)
    static let positive = Color(red: 0.30, green: 0.83, blue: 0.58)
    static let warning = Color(red: 0.96, green: 0.70, blue: 0.32)
}

struct PocketIcon: View {
    let systemImage: String
    var tint: Color = PocketLedgerTheme.accent
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

extension View {
    func pocketScreen() -> some View {
        self
            .background(PocketLedgerTheme.background.ignoresSafeArea())
            .foregroundStyle(PocketLedgerTheme.textPrimary)
            .tint(PocketLedgerTheme.accent)
            .preferredColorScheme(.dark)
    }

    func pocketCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PocketLedgerTheme.divider, lineWidth: 1)
            }
    }
}
