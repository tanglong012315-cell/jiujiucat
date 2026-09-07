import Nvwa
import SwiftUI

/// V1.2.2「切换语言」弹层（`107:2574`）：两行，选中的一行右边带勾。
///
/// 点一行就立刻写回 `LanguagePreferenceStore`，根视图的 Locale 随即更新并关闭；
/// 不需要单独的「确认」按钮，跟
/// `CurrencyPickerView` 选中即返回是同一套手感。
struct LanguagePickerSheet: View {
    @ObservedObject var store: LanguagePreferenceStore

    @Environment(\.dismiss) private var dismiss

    private enum Metrics {
        static let rowHeight: CGFloat = 56
        static let flagDiameter: CGFloat = 24
    }

    var body: some View {
        VStack(spacing: 0) {
            NvwaModalHeader("Language")
                .pawSheetMeasuredPart()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        row(language)
                    }
                }
                .padding(16)
                .pawSheetMeasuredPart()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Nvwa.backgroundDialogue)
        .pawSheetPresentation()
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
        .presentationBackground(Nvwa.backgroundDialogue)
    }

    private func row(_ language: AppLanguage) -> some View {
        let isSelected = store.selected == language

        return Button {
            store.selected = language
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(language.flagAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Metrics.flagDiameter, height: Metrics.flagDiameter)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Nvwa.line, lineWidth: 0.5))

                Text(language.title)
                    .font(Nvwa.bodyLarge)
                    .tracking(0.08)
                    .foregroundStyle(Nvwa.grayPrimary)

                Spacer(minLength: 0)

                if isSelected {
                    Image("IconCheck")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Nvwa.grayPrimary)
                }
            }
            .frame(height: Metrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(NvwaPressButtonStyle())
        .accessibilityLabel(language.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
