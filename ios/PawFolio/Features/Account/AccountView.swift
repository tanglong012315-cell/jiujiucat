import SwiftUI

struct AccountView: View {
    @ObservedObject var model: AccountViewModel
    @State private var isEditingProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    identityCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if case let .guestImportRequired(count) = model.state {
                    guestImportSection(count: count)
                } else if !model.isSignedIn {
                    signInSection
                } else {
                    profileSection
                    syncSection
                    signOutSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("账户")
            .task {
                await model.loadIfNeeded()
            }
            .sheet(isPresented: $isEditingProfile) {
                if let identity = model.identity {
                    AccountProfileEditorView(model: model, identity: identity)
                }
            }
        }
    }

    private var identityCard: some View {
        PawCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    if let identity = model.identity {
                        CatAvatarBadge(avatar: identity.avatar, size: 52)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(PawTheme.accent)
                            .frame(width: 52, height: 52)
                            .background(PawTheme.quietBlue, in: Circle())
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.identity?.displayName ?? "本机游客模式")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text(accountSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Divider()

                statusLabel
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.state {
        case .restoringSession:
            Label("正在恢复登录状态…", systemImage: "arrow.clockwise")
        case .signedOut:
            Label("持仓仅保存在这台设备", systemImage: "iphone")
        case let .signingIn(provider):
            Label("正在通过\(provider.title)登录…", systemImage: "person.badge.clock")
        case let .guestImportRequired(count):
            Label("发现 \(count) 笔游客持仓，等待你的选择", systemImage: "tray.and.arrow.down")
        case .syncing:
            Label("正在安全合并本机与云端数据…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
        case let .synchronized(holdingCount):
            Label("已同步 \(holdingCount) 笔持仓", systemImage: "checkmark.icloud")
        case let .pendingRemoteUpload(_, pendingCount):
            Label("\(pendingCount) 笔更改等待上传", systemImage: "icloud.and.arrow.up")
        case let .syncPaused(message):
            Label(message, systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private var signInSection: some View {
        Section {
            Button {
                Task { await model.signIn(using: .apple) }
            } label: {
                Label("通过 Apple 登录（等待开发者账号）", systemImage: "apple.logo")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)

            Button {
                Task { await model.signIn(using: .google) }
            } label: {
                Label("通过 Google 登录", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.isBusy)
        } header: {
            Text("跨设备同步")
        } footer: {
            Text("Google 登录使用 iOS 系统安全登录页。Apple 登录将在配置 Apple Developer Team 后启用；游客数据不会自动并入账号。")
        }
    }

    private func guestImportSection(count: Int) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Label("如何处理游客持仓？", systemImage: "pawprint.circle")
                    .font(.headline)

                Text("这台设备有 \(count) 笔游客持仓。复制会把它们加入当前账号，同时保留原游客数据；保持分开则不会上传。此选择只询问一次。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("复制到当前账号") {
                    Task { await model.chooseGuestImport(.copyIntoAccount) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)

                Button("继续保持分开") {
                    Task { await model.chooseGuestImport(.keepSeparate) }
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if let identity = model.identity {
            Section {
                LabeledContent("显示名称", value: identity.displayName)
                LabeledContent("账号", value: identity.maskedAccount)

                Button {
                    model.clearProfileError()
                    isEditingProfile = true
                } label: {
                    HStack(spacing: 12) {
                        CatAvatarBadge(avatar: identity.avatar, size: 38)
                            .accessibilityHidden(true)
                        Text("编辑名称与猫咪头像")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("编辑个人资料，当前头像为\(identity.avatar.title)")
            } header: {
                Text("个人资料")
            } footer: {
                profileSyncFooter
            }
        }
    }

    @ViewBuilder
    private var profileSyncFooter: some View {
        switch model.profileSyncState {
        case .localOnly:
            Text("个人资料当前仅保存在本机。")
        case .syncing:
            Text("正在同步个人资料；持仓同步不会受影响。")
        case .synchronized:
            Text("个人资料已同步。")
        case .pendingRemoteUpload:
            Text("个人资料已保存在本机，将在下次同步时重试上传。")
        case let .failed(message):
            Text("个人资料同步失败：\(message) 持仓同步不受影响。")
        }
    }

    private var syncSection: some View {
        Section("同步") {
            if let identity = model.identity {
                LabeledContent("登录方式", value: identity.providerName)
            }

            switch model.state {
            case let .pendingRemoteUpload(holdingCount, pendingCount):
                LabeledContent("本机持仓", value: "\(holdingCount) 笔")
                LabeledContent("等待上传", value: "\(pendingCount) 笔")
            case let .synchronized(holdingCount):
                LabeledContent("已同步持仓", value: "\(holdingCount) 笔")
            default:
                EmptyView()
            }

            Button {
                Task { await model.retrySync() }
            } label: {
                Label("立即同步", systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy || !model.isCloudSyncEnabled)
        }
    }

    private var signOutSection: some View {
        Section {
            Button("退出登录", role: .destructive) {
                Task { await model.signOut() }
            }
            .disabled(model.isBusy)
        } footer: {
            Text("退出后会切回游客持仓；账号持仓仍保留在独立的本机目录中。")
        }
    }

    private var accountSubtitle: String {
        guard let identity = model.identity else {
            return "登录后可在设备间同步，但是否导入游客数据始终由你决定。"
        }
        return identity.maskedAccount
    }
}

private struct AccountProfileEditorView: View {
    @ObservedObject var model: AccountViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var avatar: CatAvatar

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 3
    )

    init(model: AccountViewModel, identity: AccountIdentityPresentation) {
        self.model = model
        _displayName = State(initialValue: identity.displayName == "PawFolio 账户" ? "" : identity.displayName)
        _avatar = State(initialValue: identity.avatar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        CatAvatarBadge(avatar: avatar, size: 86)
                        Text(previewName)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .lineLimit(1)
                        Text(avatar.detailText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    TextField("例如：雪球", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: displayName) { _, newValue in
                            if newValue.count > 20 {
                                displayName = String(newValue.prefix(20))
                            }
                        }
                } header: {
                    Text("显示名称")
                } footer: {
                    Text("最多 20 个字符；留空时使用登录账号提供的名称。")
                }

                Section {
                    avatarGrid(CatAvatar.faceOptions)
                } header: {
                    Text("猫咪表情")
                }

                Section {
                    avatarGrid(CatAvatar.catOptions)
                } header: {
                    Text("我们家的猫")
                } footer: {
                    Text("照片随 App 安装，不会从网页加载。头像和显示名称目前只保存在这台设备。")
                }

                if let message = model.profileErrorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.isSavingProfile)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(model.isSavingProfile)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await model.saveProfile(displayName: displayName, avatar: avatar) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isSavingProfile)
                }
            }
        }
    }

    private var previewName: String {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "PawFolio 账户" : normalized
    }

    private func avatarGrid(_ options: [CatAvatar]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(options, id: \.self) { option in
                Button {
                    avatar = option
                } label: {
                    VStack(spacing: 7) {
                        CatAvatarBadge(avatar: option, size: 62)
                            .overlay(alignment: .bottomTrailing) {
                                if avatar == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, PawTheme.accent)
                                        .background(.background, in: Circle())
                                }
                            }
                        Text(option.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let subtitle = option.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityAddTraits(avatar == option ? .isSelected : [])
            }
        }
    }
}

private struct CatAvatarBadge: View {
    let avatar: CatAvatar
    let size: CGFloat

    var body: some View {
        Image(avatar.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.82), lineWidth: max(1, size * 0.025))
        }
        .accessibilityLabel(avatar.accessibilityLabel)
    }
}

private extension CatAvatar {
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
