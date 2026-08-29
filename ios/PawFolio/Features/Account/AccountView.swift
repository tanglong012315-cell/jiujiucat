import SwiftUI

/// Web 的个人资料弹层（`#profile-sheet-overlay`）。未登录时 Web 把标题换成「登录」，
/// 只留一句说明和登录按钮——改了名字头像却存不下来，比不给改更糟。
///
/// 同步状态与游客导入选择是原生特有的：Web 的同步是静默自动的，而 iOS 在移动网络下
/// 需要能看到状态并手动重试。这两块排在 Web 结构之后。
struct AccountView: View {
    @ObservedObject var model: AccountViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var draftName = ""
    @State private var draftAvatar: CatAvatar = .faceHappy
    @State private var isSignOutConfirmPresented = false
    @State private var hasLoadedDraft = false

    private let avatarColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        PawSheet(
            title: model.isSignedIn ? "个人资料" : "登录",
            // 和持仓弹层统一：破坏性操作放左上角。
            destructiveIcon: model.isSignedIn ? "IconLogout" : nil,
            destructiveLabel: "退出登录",
            onDestructive: model.isSignedIn ? { isSignOutConfirmPresented = true } : nil
        ) {
            if model.isSignedIn {
                signedInBody
            } else {
                guestNote
            }
        } footer: {
            footerButton
        }
        .task {
            await model.loadIfNeeded()
            loadDraftIfNeeded()
        }
        .onChange(of: model.identity) { _, _ in
            hasLoadedDraft = false
            loadDraftIfNeeded()
        }
        .confirmationDialog(
            "退出登录？",
            isPresented: $isSignOutConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                Task {
                    await model.signOut()
                    PawToastCenter.shared.show("已退出登录")
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机的账号数据会保留，重新登录后可以继续同步。")
        }
        .alert("资料保存失败", isPresented: profileErrorBinding) {
            Button("知道了", role: .cancel) { model.clearProfileError() }
        } message: {
            Text(model.profileErrorMessage ?? "请稍后再试。")
        }
    }

    // MARK: 已登录

    private var signedInBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                PawFieldLabel("用户名")

                PawInputShell(height: 44) {
                    TextField("未设置时显示邮箱", text: $draftName)
                        .font(PawFont.inter(14))
                        .foregroundStyle(PawTheme.ink)
                        .textInputAutocapitalization(.never)
                        .onChange(of: draftName) { _, value in
                            // Web 的 maxlength="20"。
                            if value.count > 20 { draftName = String(value.prefix(20)) }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PawFieldLabel("头像")

                LazyVGrid(columns: avatarColumns, spacing: 10) {
                    ForEach(CatAvatar.faceOptions, id: \.self) { avatar in
                        avatarOption(avatar)
                    }
                }

            }

            syncBlock

            if let identity = model.identity {
                Text("登录账号 \(identity.maskedAccount)")
                    .font(PawFont.inter(12))
                    .foregroundStyle(PawTheme.ink40)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func avatarOption(_ avatar: CatAvatar) -> some View {
        let isSelected = draftAvatar == avatar

        return Button {
            draftAvatar = avatar
        } label: {
            Image(avatar.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? PawTheme.accent : Color.white.opacity(0.82),
                            lineWidth: isSelected ? 3 : 2
                        )
                }
        }
        .buttonStyle(PawPressableButtonStyle())
        .accessibilityLabel(avatar.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 同步（原生特有）

    @ViewBuilder
    private var syncBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            PawFieldLabel("同步")

            HStack(spacing: 8) {
                Text(syncSummary)
                    .font(PawFont.inter(13))
                    .foregroundStyle(PawTheme.ink)

                Spacer(minLength: 0)

                if model.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Button("立即同步") {
                        Task {
                            await model.retrySync()
                            PawToastCenter.shared.show(syncToastMessage)
                        }
                    }
                    .font(PawFont.inter(13, weight: .medium))
                    .foregroundStyle(PawTheme.accent)
                    .buttonStyle(PawPressableButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                PawTheme.ink4,
                in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
            )

            if case .guestImportRequired(let count) = model.state {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这台设备上有 \(count) 笔游客持仓，要并入这个账号吗？")
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.ink40)

                    HStack(spacing: 8) {
                        Button("复制进账号") {
                            Task { await model.chooseGuestImport(.copyIntoAccount) }
                        }
                        .font(PawFont.inter(13, weight: .semibold))
                        .foregroundStyle(PawTheme.bg1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(PawTheme.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button("保持独立") {
                            Task { await model.chooseGuestImport(.keepSeparate) }
                        }
                        .font(PawFont.inter(13))
                        .foregroundStyle(PawTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(PawTheme.ink4, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(PawPressableButtonStyle())
                }
            }
        }
    }

    /// 同步完成后的反馈，直接复用状态机给出的结论。
    private var syncToastMessage: String {
        switch model.state {
        case .synchronized(let count): "已同步 \(count) 笔持仓"
        case .pendingRemoteUpload(_, let pending): "还有 \(pending) 笔待上传"
        case .failed(let message): message
        default: syncSummary
        }
    }

    private var syncSummary: String {
        switch model.state {
        case .restoringSession: "正在恢复登录…"
        case .signedOut: "未登录"
        case .signingIn: "正在登录…"
        case .guestImportRequired: "等待选择游客数据去向"
        case .syncing: "正在同步…"
        case .synchronized(let count): "已同步 \(count) 笔持仓"
        case .pendingRemoteUpload(let count, let pending): "已同步 \(count) 笔，\(pending) 笔待上传"
        case .syncPaused(let message): message
        case .failed(let message): message
        }
    }

    // MARK: 未登录

    private var guestNote: some View {
        VStack(spacing: 16) {
            Image("ArtLogin")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel("未登录")

            Text("登录后可以自定义用户名和头像，持仓也会同步到云端。")
                .font(PawFont.inter(13))
                .foregroundStyle(PawTheme.ink40)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: 底部按钮

    @ViewBuilder
    private var footerButton: some View {
        if model.isSignedIn {
            PawPrimaryButton(title: model.isSavingProfile ? "保存中…" : "保存") {
                Task {
                    let saved = await model.saveProfile(
                        displayName: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
                        avatar: draftAvatar
                    )
                    if saved {
                        PawToastCenter.shared.show("个人资料已保存")
                        dismiss()
                    }
                }
            }
            .disabled(model.isSavingProfile)
        } else {
            PawPrimaryButton(title: "登录") {
                Task { await model.signIn(using: .google) }
            }
        }
    }

    // MARK: 草稿

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft, let identity = model.identity else { return }
        draftName = identity.displayName
        draftAvatar = identity.avatar
        hasLoadedDraft = true
    }

    private var profileErrorBinding: Binding<Bool> {
        Binding(
            get: { model.profileErrorMessage != nil },
            set: { if !$0 { model.clearProfileError() } }
        )
    }
}

private struct CatAvatarBadge: View {
    let avatar: CatAvatar
    let size: CGFloat
    /// 与正文并排时随 Dynamic Type 缩放；头像选择网格保持固定尺寸以免破坏网格。
    var scalesWithText = false

    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1

    private var diameter: CGFloat {
        scalesWithText ? size * min(scale, 1.6) : size
    }

    var body: some View {
        Image(avatar.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.82), lineWidth: max(1, diameter * 0.025))
        }
        .accessibilityLabel(avatar.accessibilityLabel)
    }
}

// 头像的展示信息现在也给头部用（Web 的 `.header-avatar`），所以不再是 fileprivate。
extension CatAvatar {
    var title: String {
        switch self {
        case .faceHappy: "开心"
        case .faceCute: "可爱"
        case .faceLove: "心动"
        case .faceThinking: "思考"
        case .faceSleepy: "困了"
        case .faceSurprised: "惊讶"
        case .faceCrying: "哭泣"
        case .faceAngry: "生气"
        case .faceHorn: "小恶魔"
        case .catPuffy: "Puffy"
        case .catNono: "NoNo"
        case .catJiujiu: "JiuJiu"
        case .catLiz: "Liz"
        case .catPudding: "Pudding"
        case .catZhezhe: "ZheZhe"
        case .catCoco: "CoCo"
        case .catMomo: "MoMo"
        case .catBobo: "BoBo"
        }
    }

    var subtitle: String? {
        switch self {
        case .catPuffy: "元老教母"
        case .catNono: "不喜欢同性"
        case .catJiujiu: "大眼萌妹"
        case .catLiz: "别名 Mini"
        case .catPudding: "娘娘腔，种公"
        case .catZhezhe: "疯P"
        case .catCoco: "脾气暴躁"
        case .catMomo: "小公主"
        case .catBobo: "小少爷"
        default: nil
        }
    }

    var detailText: String {
        switch self {
        case .catPuffy: "Puffy · 元老教母 · 母猫 · 2017.09.17 生"
        case .catNono: "NoNo · 不喜欢同性 · 公猫 · 2022.05.17 生"
        case .catJiujiu: "JiuJiu · 大眼萌妹 · 母猫 · 2022.10.03 生"
        case .catLiz: "Liz · 别名 Mini · 母猫 · 2023.10.15 生"
        case .catPudding: "Pudding · 娘娘腔，种公 · 公猫 · 2023.03.02 生"
        case .catZhezhe: "ZheZhe · 疯P · 公猫 · 2025 年生"
        case .catCoco: "CoCo · 脾气暴躁 · 母猫 · 2024.01.15 生"
        case .catMomo: "MoMo · 小公主 · 母猫 · 2025.11.09 生"
        case .catBobo: "BoBo · 小少爷 · 公猫 · 2025.11.09 生"
        default: "\(title)猫咪表情"
        }
    }

    var accessibilityLabel: String {
        "\(detailText)头像"
    }

    var assetName: String {
        switch self {
        case .faceHappy: "ProfileFaceHappy"
        case .faceCute: "ProfileFaceCute"
        case .faceLove: "ProfileFaceLove"
        case .faceThinking: "ProfileFaceThinking"
        case .faceSleepy: "ProfileFaceSleepy"
        case .faceSurprised: "ProfileFaceSurprised"
        case .faceCrying: "ProfileFaceCrying"
        case .faceAngry: "ProfileFaceAngry"
        case .faceHorn: "ProfileFaceHorn"
        case .catPuffy: "ProfileCatPuffy"
        case .catNono: "ProfileCatNono"
        case .catJiujiu: "ProfileCatJiuJiu"
        case .catLiz: "ProfileCatLiz"
        case .catPudding: "ProfileCatPudding"
        case .catZhezhe: "ProfileCatZheZhe"
        case .catCoco: "ProfileCatCoco"
        case .catMomo: "ProfileCatMomo"
        case .catBobo: "ProfileCatBobo"
        }
    }
}

private extension AuthenticationProvider {
    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}
