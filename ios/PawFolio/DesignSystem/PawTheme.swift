import SwiftUI

enum PawTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)
            : UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
    })
    static let quietBlue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 125 / 255, green: 187 / 255, blue: 1, alpha: 0.16)
            : UIColor(red: 230 / 255, green: 241 / 255, blue: 253 / 255, alpha: 1)
    })
    static let gain = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 61 / 255, green: 220 / 255, blue: 132 / 255, alpha: 1)
            : UIColor(red: 18 / 255, green: 128 / 255, blue: 63 / 255, alpha: 1)
    })
    static let loss = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 248 / 255, green: 113 / 255, blue: 113 / 255, alpha: 1)
            : UIColor(red: 192 / 255, green: 57 / 255, blue: 43 / 255, alpha: 1)
    })

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 12
    static let contentWidth: CGFloat = 760
}

struct PawCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: PawTheme.cardRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
    }
}

struct PawSectionHeading: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .semibold))

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PawFeatureScaffold: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(message)
            }
            .navigationTitle(title)
        }
    }
}
