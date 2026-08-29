import SwiftUI

/// Web 的「我们家的猫」弹层（`#cat-sheet-overlay`）：点一只设成头像，长按看大图。
struct CatGallerySheet: View {
    let selected: CatAvatar?
    let onChoose: (CatAvatar) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var previewed: CatProfile? = {
        #if DEBUG
        // 视觉 QA：长按手势没法用截图验证，用 `SIMCTL_CHILD_PAWFOLIO_PREVIEW_CAT=<id>` 直接打开大图。
        if let id = ProcessInfo.processInfo.environment["PAWFOLIO_PREVIEW_CAT"] {
            return CatProfile.profile(id: id)
        }
        #endif
        return nil
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        PawSheet(title: "我们家的猫") {
            VStack(alignment: .leading, spacing: 16) {
                Text("这是我们家的九只猫。点一只设成头像，长按看大图。")
                    .font(PawFont.inter(12))
                    .foregroundStyle(PawTheme.ink40)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(CatProfile.all) { cat in
                        cell(for: cat)
                    }
                }
            }
        }
        .overlay {
            if let previewed {
                photoViewer(for: previewed)
            }
        }
    }

    private func cell(for cat: CatProfile) -> some View {
        let avatar = CatAvatar.avatar(for: cat)

        return Button {
            guard let avatar else { return }
            onChoose(avatar)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                photo(for: cat)

                HStack(spacing: 4) {
                    Text(cat.name)
                        .font(PawFont.inter(12, weight: .medium))
                        .foregroundStyle(PawTheme.ink)

                    sexMark(cat.sex)
                }

                Text(cat.detail)
                    .font(PawFont.inter(11))
                    .foregroundStyle(PawTheme.ink40)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PawPressableButtonStyle())
        .onLongPressGesture {
            previewed = cat
        }
        .accessibilityLabel("\(cat.name)，\(cat.detail)，\(cat.sex.title)")
        .accessibilityHint("点按设为头像，长按看大图")
        .accessibilityAddTraits(avatar == selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Web `.cat-photo`：洗出来的相片——直角、4pt 白边，外加全站唯一的投影。
    private func photo(for cat: CatProfile) -> some View {
        GeometryReader { geometry in
            let side = geometry.size.width * 0.86

            Group {
                if let avatar = CatAvatar.avatar(for: cat) {
                    Image(avatar.assetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    PawTheme.ink4
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .border(Color.white, width: 4)
            .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 2)
            .shadow(color: .black.opacity(0.34), radius: 10, x: 0, y: 6)
            .overlay(alignment: .topLeading) {
                // 选中的那只补一圈描边，和头像网格的选中态一致。
                if CatAvatar.avatar(for: cat) == selected {
                    Rectangle()
                        .strokeBorder(PawTheme.accent, lineWidth: 2)
                        .frame(width: side, height: side)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 性别图标：粉=母、蓝=公。Web 注释写明这组色不随主题走。
    private func sexMark(_ sex: CatProfile.Sex) -> some View {
        Image(sex == .female ? "IconWomen" : "IconMen")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 13, height: 13)
            .foregroundStyle(
                sex == .female
                    ? Color(red: 224 / 255, green: 98 / 255, blue: 155 / 255)
                    : Color(red: 74 / 255, green: 144 / 255, blue: 226 / 255)
            )
    }

    /// Web `.photo-viewer`：全屏压暗，相片用 6pt 白边。
    private func photoViewer(for cat: CatProfile) -> some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { previewed = nil }

            VStack(spacing: 12) {
                if let avatar = CatAvatar.avatar(for: cat) {
                    Image(avatar.assetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: 420, maxHeight: 520)
                        .border(Color.white, width: 6)
                        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
                }

                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Text(cat.name)
                            .font(PawFont.inter(15, weight: .semibold))
                            .foregroundStyle(.white)

                        sexMark(cat.sex)
                    }

                    Text(cat.detail)
                        .font(PawFont.inter(12))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(
                        [CatAgeFormatter.ageText(birth: cat.birth), CatAgeFormatter.birthText(birth: cat.birth)]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                    .font(PawFont.inter(12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { previewed = nil }
    }
}

extension CatAvatar {
    /// `cat:` 前缀的头像背后那只猫。表情头像返回 nil。
    var catProfile: CatProfile? {
        guard rawValue.hasPrefix("cat:") else { return nil }
        return CatProfile.profile(id: String(rawValue.dropFirst(4)))
    }

    static func avatar(for profile: CatProfile) -> CatAvatar? {
        CatAvatar(rawValue: "cat:\(profile.id)")
    }
}
