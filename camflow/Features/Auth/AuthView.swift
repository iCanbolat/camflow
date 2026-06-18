import SwiftUI
import SwiftData
import AuthenticationServices
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Sign in / sign up with email-password, Apple, or Google. On success it hands
/// the resolved `Account` to `Session`; the root coordinator then advances to
/// org creation or the app.
struct AuthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session
    @Environment(AppServices.self) private var services

    private enum Mode: Hashable {
        case signIn
        case signUp
    }

    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isShowingResetInfo = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isShowingCodeEntry = false
    @State private var clipboardCode: String?
    @State private var isShowingGoogleNotice = false

    private var service: any AuthService { services.authService }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isWorking &&
            (mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                Picker("", selection: $mode) {
                    Text("Sign In").tag(Mode.signIn)
                    Text("Sign Up").tag(Mode.signUp)
                }
                .pickerStyle(.segmented)

                fields

                Button(action: submit) {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(mode == .signIn ? "Sign In" : "Create Account")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit)

                dividerRow

                socialButtons

                Button("Have an invite code?") { isShowingCodeEntry = true }
                    .font(.footnote.weight(.medium))

                #if DEBUG
                // Cloud auth is now the only real path. For offline simulator
                // work this seeds the local demo data and signs into the seeded
                // account directly (no backend), bypassing the network.
                Button("Sign in as demo (DEBUG)") {
                    DebugSupport.seedSampleData(context: modelContext)
                    let descriptor = FetchDescriptor<Account>(
                        predicate: #Predicate { $0.email == "demo@camflow.app" && $0.deletedAt == nil }
                    )
                    if let account = (try? modelContext.fetch(descriptor))?.first {
                        session.signIn(account)
                    }
                }
                .font(.footnote.weight(.medium))
                .tint(.secondary)
                .disabled(isWorking)
                #endif
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .animation(.default, value: mode)
        .sheet(isPresented: $isShowingCodeEntry) {
            InviteCodeEntrySheet()
        }
        .task {
            guard session.pendingInviteCode == nil else { return }
            clipboardCode = await InviteClipboard.detectInviteCode()
        }
        .alert(
            "Join with invite code \(clipboardCode ?? "")?",
            isPresented: Binding(get: { clipboardCode != nil }, set: { if !$0 { clipboardCode = nil } })
        ) {
            Button("Join") {
                session.setPendingInvite(code: clipboardCode)
                clipboardCode = nil
            }
            Button("Not Now", role: .cancel) { clipboardCode = nil }
        } message: {
            Text("We found a CamFlow invite link on your clipboard. Sign in to join the team.")
        }
        .alert("Forgot Password", isPresented: $isShowingResetInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Password reset arrives soon. For now, sign in with Apple, or create a new account.")
        }
        .alert("Google Sign-In", isPresented: $isShowingGoogleNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Google sign-in is coming soon. Please use email or Apple for now.")
        }
        .alert(
            "Sign-in failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image("CamFlowIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
            Text("Welcome to CamFlow")
                .font(.title2.bold())
            Text("Sign in to sync your projects across your team.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if session.pendingInviteCode != nil {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.open")
                    Text("You've been invited — sign in to join the team.")
                        .font(.footnote.weight(.medium))
                    Button {
                        session.setPendingInvite(code: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 14) {
            if mode == .signUp {
                AuthInputRow(icon: "person") {
                    TextField("Full name", text: $displayName)
                        .textContentType(.name)
                }
            }
            AuthInputRow(icon: "envelope") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            AuthInputRow(icon: "lock") {
                Group {
                    if isPasswordVisible {
                        TextField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textContentType(mode == .signIn ? .password : .newPassword)

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if mode == .signIn {
                Button("Forgot password?") { isShowingResetInfo = true }
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var dividerRow: some View {
        HStack {
            VStack { Divider() }
            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            }
            .disabled(isWorking)

            Button {
                #if canImport(GoogleSignIn)
                Task { await handleGoogle() }
                #else
                isShowingGoogleNotice = true
                #endif
            } label: {
                HStack(spacing: 10) {
                    GoogleGIcon(size: 18)
                    Text("Continue with Google")
                        .font(.system(size: 19, weight: .medium))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
    }

    // MARK: - Actions

    private func submit() {
        let name = displayName
        let mode = mode
        authenticate {
            switch mode {
            case .signIn:
                return try await service.signIn(email: email, password: password)
            case .signUp:
                return try await service.signUp(email: email, password: password, displayName: name)
            }
        }
    }

    /// Exchanges the Apple credential's identity token with the backend.
    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = String(localized: "Apple sign-in didn't return a valid token.")
                return
            }
            let displayName = credential.fullName.map {
                PersonNameComponentsFormatter().string(from: $0)
            }?.nilIfBlank
            authenticate { try await service.signInWithApple(identityToken: token, displayName: displayName) }
        case let .failure(error):
            // A user-cancelled flow isn't worth surfacing as an error.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if canImport(GoogleSignIn)
    /// Presents Google Sign-In, then exchanges the returned id token with the
    /// backend (which verifies it against `GOOGLE_CLIENT_ID`).
    @MainActor
    private func handleGoogle() async {
        guard !isWorking else { return }
        guard let presenter = Self.topViewController() else {
            errorMessage = String(localized: "Couldn't present Google sign-in.")
            return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = String(localized: "Google sign-in didn't return a valid token.")
                return
            }
            authenticate { try await service.signInWithGoogle(idToken: idToken) }
        } catch let error as GIDSignInError where error.code == .canceled {
            // User dismissed the sheet — not an error worth surfacing.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Topmost presented controller of the active foreground scene (Google's SDK
    /// needs a presenter and SwiftUI doesn't hand us one directly).
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif

    private func authenticate(_ operation: @escaping () async throws -> Account) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let account = try await operation()
                // Pull the account's orgs + members before routing so the
                // coordinator lands on the app (not org creation) for returners.
                await services.hydrate()
                session.signIn(account)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension String {
    /// nil when the string is empty or only whitespace.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Rounded input card with a leading SF Symbol adornment, shared by the
/// auth screens so they read as one family.
struct AuthInputRow<Content: View>: View {
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            content
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// The multicolor Google "G", drawn with trimmed circle strokes so no image
/// asset is needed. The gap before 3 o'clock plus the crossbar form the "G".
struct GoogleGIcon: View {
    var size: CGFloat = 18

    private static let blue = Color(red: 0.259, green: 0.522, blue: 0.957)
    private static let red = Color(red: 0.918, green: 0.263, blue: 0.208)
    private static let yellow = Color(red: 0.984, green: 0.737, blue: 0.02)
    private static let green = Color(red: 0.204, green: 0.659, blue: 0.325)

    var body: some View {
        ZStack {
            segment(from: 0, to: 0.25, color: Self.green)
            segment(from: 0.25, to: 0.5, color: Self.yellow)
            segment(from: 0.5, to: 0.75, color: Self.red)
            segment(from: 0.75, to: 0.93, color: Self.blue)
            Rectangle()
                .fill(Self.blue)
                .frame(width: size * 0.48, height: size * 0.21)
                .offset(x: size * 0.24)
        }
        .frame(width: size, height: size)
    }

    private func segment(from: CGFloat, to: CGFloat, color: Color) -> some View {
        Circle()
            .inset(by: size * 0.105)
            .trim(from: from, to: to)
            .stroke(color, lineWidth: size * 0.21)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Account.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let session = Session(context: container.mainContext)
    return AuthView()
        .modelContainer(container)
        .environment(session)
        .environment(AppServices(modelContext: container.mainContext, session: session))
}
