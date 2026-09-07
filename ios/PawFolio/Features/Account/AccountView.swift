import Nvwa
import SwiftUI

/// Figma V1.1 account screen (`47:2085`). The screen is presented full-screen
/// and deliberately uses Nvwa navigation, input, section, and button components.
struct AccountView: View {
    @ObservedObject var model: AccountViewModel
    @ObservedObject var themeController: NvwaThemeController
    @ObservedObject var languageStore: LanguagePreferenceStore

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var draftName = ""
    @State private var draftAvatar: CatAvatar = .faceHappy
    @State private var isSignOutConfirmPresented = false
    @State private var isLanguagePickerPresented = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_QA_LANGUAGE_PICKER"] == "1"
        #else
        return false
        #endif
    }()
    @State private var hasLoadedDraft = false

    private let avatarColumns = Array(
        repeating: GridItem(.flexible(), spacing: 24),
        count: 5
    )

    var body: some View {
        Group {
            if isSignedIn {
                VStack(spacing: 0) {
                    navigationBar

                    ScrollView {
                        signedInBody
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                ZStack(alignment: .top) {
                    signedOutBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    navigationBar
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Nvwa.backgroundMain)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSignedIn {
                footer
            }
        }
        .task {
            if visualQAIdentity == nil {
                await model.loadIfNeeded()
            }
            loadDraftIfNeeded()
        }
        .onChange(of: model.identity) { _, _ in
            hasLoadedDraft = false
            loadDraftIfNeeded()
        }
        .sheet(isPresented: $isLanguagePickerPresented) {
            LanguagePickerSheet(store: languageStore)
                .preferredColorScheme(themeController.preference)
        }
        .confirmationDialog(
            "Log out?",
            isPresented: $isSignOutConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                Task {
                    await model.signOut()
                    PawToastCenter.shared.show("Logged out")
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account data will stay on this device and can sync again after you log in.")
        }
        .alert("Couldn’t save profile", isPresented: profileErrorBinding) {
            Button("OK", role: .cancel) { model.clearProfileError() }
        } message: {
            Text(LocalizedStringKey(model.profileErrorMessage ?? "Please try again later."))
        }
    }

    private var navigationBar: some View {
        NvwaNavigationBar(
            leading: .icon(
                Image("IconClose"),
                accessibilityLabel: "Close",
                action: { dismiss() }
            ),
            trailing: [
                .icon(
                    Image(themeController.targetAppearanceIconName(systemScheme: colorScheme)),
                    accessibilityLabel: "Toggle appearance",
                    action: toggleAppearance
                ),
                .artwork(
                    Image(languageStore.selected.flagAssetName),
                    accessibilityLabel: "Change language",
                    action: { isLanguagePickerPresented = true }
                )
            ]
        )
    }

    private var signedInBody: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(spacing: 10) {
                NvwaAvatar(
                    initials: initials,
                    // 选中的猫立刻预览，不用等 Save 落库。
                    image: draftAvatar.portraitImage,
                    diameter: 120,
                    typography: Nvwa.Typography.titleScreen
                )
                    // V1.2.2 (`106:2398`) 把这个头像大小改成了 120pt。Nvwa Avatar
                    // 组件本身在库里仍是 42pt 那一档权威定义，这里继续只在产品页面
                    // 覆盖尺寸，不回头改库的默认值。
                    .frame(height: 120)
                    .accessibilityLabel(
                        draftAvatar.isPortrait ? draftAvatar.accessibilityLabel : initials
                    )

                Text("Signed in as \(displayedIdentity?.maskedAccount ?? "—")")
                    .font(Nvwa.bodySmall)
                    .tracking(0.12)
                    .foregroundStyle(Nvwa.graySecondary)
            }
            .frame(maxWidth: .infinity)

            NvwaInputField(
                label: "User Name",
                placeholder: "User name",
                text: $draftName
            )
            .onChange(of: draftName) { _, value in
                if value.count > 20 {
                    draftName = String(value.prefix(20))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Avatar")

                LazyVGrid(columns: avatarColumns, spacing: 12) {
                    defaultAvatarOption
                    ForEach(CatAvatar.catOptions, id: \.self) { avatar in
                        avatarOption(avatar)
                    }
                }
            }

            if let recoveryState {
                syncRecoveryBlock(recoveryState)
            }
        }
    }

    @ViewBuilder
    private func syncRecoveryBlock(_ state: AccountRecoveryState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .guestImport(let count):
                if count == 1 {
                    NvwaHint(localizedText: "This device has \(count) guest position. Copy it to this account?")
                } else {
                    NvwaHint(localizedText: "This device has \(count) guest positions. Copy them to this account?")
                }

                HStack(spacing: 12) {
                    NvwaButton(
                        "Copy to Account",
                        kind: .primary,
                        size: .small,
                        expandsHorizontally: true
                    ) {
                        Task { await model.chooseGuestImport(.copyIntoAccount) }
                    }

                    NvwaButton(
                        "Keep Separate",
                        kind: .secondary,
                        size: .small,
                        expandsHorizontally: true
                    ) {
                        Task { await model.chooseGuestImport(.keepSeparate) }
                    }
                }

            case .holdingUploadPending(let count):
                if count == 1 {
                    retrySyncBlock(message: "\(count) change still needs to upload.")
                } else {
                    retrySyncBlock(message: "\(count) changes still need to upload.")
                }

            case .profileUploadPending:
                retrySyncBlock(message: "Profile changes still need to sync.")
            }
        }
    }

    private func retrySyncBlock(message: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NvwaHint(localizedText: message)

            NvwaButton(
                "Retry Sync",
                kind: .secondary,
                size: .small,
                expandsHorizontally: true
            ) {
                Task { await model.retrySync() }
            }
        }
    }

    private var signedOutBody: some View {
        NvwaButton(
            "Login with Google",
            kind: .outline,
            size: .huge,
            leadingIcon: Image("IconGoogle")
        ) {
            Task { await model.signIn(using: .google) }
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            NvwaButton(
                "Save",
                kind: .outline,
                size: .huge,
                expandsHorizontally: true,
                isLoading: model.isSavingProfile
            ) {
                saveProfile()
            }
            .disabled(model.isSavingProfile)
            .accessibilityValue(model.isSavingProfile ? "Saving" : "")

            Button("Log Out") {
                isSignOutConfirmPresented = true
            }
            // 设计稿 139:1325 用的是 T-G Medium（14/20，1.5% 字距），不是按钮字号。
            .nvwaTextStyle(Nvwa.Typography.titleGroup)
            .foregroundStyle(Nvwa.sentimentNegative)
            .frame(height: 20)
            .buttonStyle(NvwaPressButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Nvwa.backgroundMain)
    }

    private var defaultAvatarOption: some View {
        Button {
            draftAvatar = .faceHappy
        } label: {
            Text(initials)
                .font(Nvwa.font(16, weight: .semibold))
                .tracking(0.08)
                .foregroundStyle(Nvwa.grayPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Nvwa.backgroundVessel, in: Circle())
                .overlay {
                    selectionRing(isSelected: !CatAvatar.catOptions.contains(draftAvatar))
                }
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(NvwaPressButtonStyle())
        .accessibilityLabel("Use initials as avatar")
        .accessibilityAddTraits(
            !CatAvatar.catOptions.contains(draftAvatar) ? [.isButton, .isSelected] : .isButton
        )
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Circle())
                .overlay {
                    selectionRing(isSelected: isSelected)
                }
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(NvwaPressButtonStyle())
        .accessibilityLabel(avatar.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func selectionRing(isSelected: Bool) -> some View {
        // V1.2.2 (`106:2405`) 把选中描边从 1pt 加粗到 2pt；颜色是 `text/primary`
        // （黑/白跟随主题），不是核心蓝——「primary」在这条批注里指的是文字色阶，
        // 不是 `primaryGreen` 那个品牌蓝，两者撞了名字，用户 2026-09-03 纠正过。
        //
        // `.animation(nil, ...)` 是特意按上的：选中态要一点开就在，不要有过渡——
        // 用户明确要求去掉这里的选中动画。
        Circle()
            .strokeBorder(
                isSelected ? Nvwa.grayPrimary : Color.clear,
                lineWidth: 2
            )
            .animation(nil, value: isSelected)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(Nvwa.bodySmall)
            .tracking(0.12)
            .foregroundStyle(Nvwa.graySecondary)
    }

    private var initials: String {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "PF" }
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func toggleAppearance() {
        themeController.toggle(systemScheme: colorScheme)
    }

    private var recoveryState: AccountRecoveryState? {
        switch model.state {
        case .guestImportRequired(let count):
            return .guestImport(count: count)
        case .pendingRemoteUpload(_, let pendingCount):
            return .holdingUploadPending(count: pendingCount)
        case .failed:
            break
        default:
            break
        }

        switch model.profileSyncState {
        case .pendingRemoteUpload:
            return .profileUploadPending
        case .failed:
            return nil
        default:
            return nil
        }
    }

    private func saveProfile() {
        #if DEBUG
        if visualQAIdentity != nil {
            PawToastCenter.shared.show("Profile saved")
            return
        }
        #endif

        Task {
            let saved = await model.saveProfile(
                displayName: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
                avatar: draftAvatar
            )
            if saved {
                PawToastCenter.shared.show("Profile saved")
                dismiss()
            }
        }
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft, let identity = displayedIdentity else { return }
        draftName = identity.displayName
        draftAvatar = identity.avatar
        hasLoadedDraft = true
    }

    private var isSignedIn: Bool {
        displayedIdentity != nil
    }

    private var displayedIdentity: AccountIdentityPresentation? {
        visualQAIdentity ?? model.identity
    }

    private var visualQAIdentity: AccountIdentityPresentation? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["PAWFOLIO_QA_ACCOUNT"] == "1" else {
            return nil
        }
        return AccountIdentityPresentation(
            displayName: "TL",
            maskedAccount: "ta@gmail.com",
            providerName: "Google",
            avatar: .catMomo
        )
        #else
        return nil
        #endif
    }

    private var profileErrorBinding: Binding<Bool> {
        Binding(
            get: { model.profileErrorMessage != nil },
            set: { if !$0 { model.clearProfileError() } }
        )
    }
}

/// Figma V1.1 full-screen authentication state (`90:11162` / `92:13272`).
///
/// The OAuth request stays owned by this presentation. Dismissing the page
/// cancels the in-flight task, while an authentication error keeps the page
/// visible so the user can retry instead of being dropped back at Portfolio.
/// V1.2.2（`107:2589` 空闲态 / `133:6921` 登录中态）重画：去掉了 V1.1 那块蓝色
/// 背景和「Welcome Back」大标题——批注原文「去掉界面大蓝色，去掉标题和副标题」。
/// V1.2.3（`173:22119`）进一步把等待拆成两段：OAuth 尚未完成时只显示原生菊花；
/// 身份已经建立、开始加载云端数据后，才显示「Welcome Back / Your Data is protected.」。
/// 两段等待态都收起顶栏，避免异步操作期间重复触发关闭、主题或语言操作。
///
/// **这一步本来就会等到云端同步落定**，不是这次新加的等待逻辑：
/// `AccountViewModel.signIn(using:)` 内部一路 `await` 到
/// `prepareAuthenticatedSession` 把持仓、资料都同步完（或者停在
/// `.guestImportRequired` / `.syncPaused` 这类需要用户在个人中心页自己做决定的
/// 节点）才返回，`isBusy` 全程跟着这一整段异步操作，不是只包住网络请求那一下。
/// 这里仍只调整展示阶段，OAuth 和同步的异步边界没有改动。
enum LoginPresentationPhase: Equatable {
    case idle
    case authenticating
    case loadingAccount

    init(state: AccountSyncPresentationState, isSignedIn: Bool) {
        switch state {
        case .restoringSession, .signingIn:
            self = isSignedIn ? .loadingAccount : .authenticating
        case .syncing:
            self = .loadingAccount
        default:
            self = .idle
        }
    }
}

struct LoginView: View {
    @ObservedObject var model: AccountViewModel
    @ObservedObject var themeController: NvwaThemeController
    @ObservedObject var languageStore: LanguagePreferenceStore

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var loginAttempt = 0
    @State private var isLanguagePickerPresented = false

    private var qaPresentationPhase: LoginPresentationPhase? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_LOGIN_AUTHENTICATING"] == "1" {
            return .authenticating
        }
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_LOGIN_WAITING"] == "1" {
            return .loadingAccount
        }
        return nil
        #else
        return nil
        #endif
    }

    private var presentationPhase: LoginPresentationPhase {
        qaPresentationPhase
            ?? LoginPresentationPhase(state: model.state, isSignedIn: model.isSignedIn)
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch presentationPhase {
            case .authenticating:
                authenticatingContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loadingAccount:
                waitingContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .idle:
                idleContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                navigationBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Nvwa.backgroundMain)
        .sheet(isPresented: $isLanguagePickerPresented) {
            LanguagePickerSheet(store: languageStore)
                .preferredColorScheme(themeController.preference)
        }
        .task(id: loginAttempt) {
            guard loginAttempt > 0 else { return }
            await model.signIn(using: .google)
            guard !Task.isCancelled else { return }
            if model.isSignedIn {
                dismiss()
            }
        }
        .onChange(of: model.isSignedIn) { _, isSignedIn in
            // Session restoration may finish while the page is opening. During
            // a user-started login, wait for `signIn` to finish its sync work;
            // dismissing here would cancel the presentation-owned task early.
            if isSignedIn, loginAttempt == 0 {
                dismiss()
            }
        }
        .onChange(of: authenticationMessage) { _, message in
            // 一次性提示，不是常驻控件：原来是把它摆在按钮下面常驻显示，取消登录
            // 之后 `state` 停在 `.failed` 不会自己走开，那条提示就再也不消失了
            // （用户 2026-09-03 报的）。Toast 本身就是「出现一下自己收起」，
            // 用它就不用另外写一段「什么时候该把提示收掉」的逻辑。
            guard let message else { return }
            PawToastCenter.shared.show(message)
        }
    }

    private var navigationBar: some View {
        NvwaNavigationBar(
            leading: .icon(
                Image("IconClose"),
                accessibilityLabel: "Close",
                action: { dismiss() }
            ),
            trailing: [
                .icon(
                    Image(themeController.targetAppearanceIconName(systemScheme: colorScheme)),
                    accessibilityLabel: "Toggle appearance",
                    action: toggleAppearance
                ),
                .artwork(
                    Image(languageStore.selected.flagAssetName),
                    accessibilityLabel: "Change language",
                    action: { isLanguagePickerPresented = true }
                )
            ]
        )
    }

    private var idleContent: some View {
        NvwaButton(
            "Login with Google",
            kind: .outline,
            size: .huge,
            leadingIcon: Image("IconGoogle")
        ) {
            loginAttempt += 1
        }
        .accessibilityValue("Ready")
    }

    /// `173:22119`：OAuth 返回前只显示菊花，不提前展示 Welcome 文案。
    private var authenticatingContent: some View {
        appLoadingIndicator(accessibilityLabel: "Signing in")
    }

    /// `133:6921`：身份已建立后，云端数据加载期间显示 Welcome 和菊花。
    private var waitingContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Welcome Back")
                    .font(Nvwa.font(30, weight: .semibold))
                    .tracking(-0.75)
                    .foregroundStyle(Nvwa.primaryGreen)
                    .frame(height: 34)

                Text("Your Data is protected.")
                    .font(Nvwa.font(14))
                    .tracking(0.14)
                    .foregroundStyle(Nvwa.graySecondary)
                    .frame(height: 22)
            }

            appLoadingIndicator(accessibilityLabel: "Loading account data")
        }
        .frame(width: 343)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome back, loading your protected data")
    }

    private func appLoadingIndicator(accessibilityLabel: LocalizedStringKey) -> some View {
        PawAppLoadingIndicator(accessibilityLabel)
    }

    private var authenticationMessage: String? {
        guard loginAttempt > 0,
              case let .failed(message) = model.state,
              !model.isSignedIn else {
            return nil
        }
        return message
    }

    private func toggleAppearance() {
        themeController.toggle(systemScheme: colorScheme)
    }
}

private enum AccountRecoveryState {
    case guestImport(count: Int)
    case holdingUploadPending(count: Int)
    case profileUploadPending
}

extension CatAvatar {
    var title: String {
        switch self {
        case .faceHappy: "Happy"
        case .faceCute: "Cute"
        case .faceLove: "In Love"
        case .faceThinking: "Thinking"
        case .faceSleepy: "Sleepy"
        case .faceSurprised: "Surprised"
        case .faceCrying: "Crying"
        case .faceAngry: "Angry"
        case .faceHorn: "Mischievous"
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

    var detailText: String {
        catProfile.map {
            "\($0.name) · \($0.detail) · \($0.sex.title) · \($0.birth)"
        } ?? title
    }

    var accessibilityLabel: String {
        "\(detailText) avatar"
    }

    /// 只有猫图鉴里的九只会真的当头像画出来。`face*` 那九张是「我们家的猫」
    /// 状态插画，个人中心用它们表示「用首字母」，所以这里给 nil。
    var isPortrait: Bool { Self.catOptions.contains(self) }

    /// 头像位要显示的图；用首字母时为 nil。
    var portraitImage: Image? {
        isPortrait ? Image(assetName) : nil
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
