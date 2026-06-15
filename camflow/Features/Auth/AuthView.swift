import SwiftUI
import SwiftData
import AuthenticationServices

/// Sign in / sign up with email-password, Apple, or Google. On success it hands
/// the resolved `Account` to `Session`; the root coordinator then advances to
/// org creation or the app.
struct AuthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

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

    private var service: any AuthService { MockAuthService(context: modelContext) }

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
                // A plain Xcode Run passes no launch arguments, so the store is
                // empty and the seeded demo account doesn't exist — manual
                // demo sign-in then fails with "No account found". This seeds it
                // on demand and signs in through the normal auth path.
                Button("Sign in as demo (DEBUG)") {
                    DebugSupport.seedSampleData(context: modelContext)
                    email = DebugSupport.demoEmail
                    password = DebugSupport.demoPassword
                    authenticate {
                        try await service.signIn(
                            email: DebugSupport.demoEmail,
                            password: DebugSupport.demoPassword
                        )
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
            Text("Password reset arrives with cloud sync. For now, sign in with Apple or Google, or create a new account.")
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
            SignInWithAppleButton(.continue) { _ in
            } onCompletion: { _ in
                // The scaffold resolves a local Apple account regardless of the
                // real credential result.
                authenticate { try await service.signInWithApple() }
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
                authenticate { try await service.signInWithGoogle() }
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

    private func authenticate(_ operation: @escaping () async throws -> Account) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let account = try await operation()
                session.signIn(account)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
    return AuthView()
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
