import SwiftUI
import Core
import Services

public struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isSignupMode = false
    @State private var username = ""
    @State private var rememberMe = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, username, password
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .padding(.bottom, 20)

                Text("SwiftGTD")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                VStack(spacing: 15) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .email)
                        .onSubmit {
                            focusedField = isSignupMode && !username.isEmpty ? .username : .password
                        }
                        #if os(macOS)
                        .frame(maxWidth: 300)
                        #endif
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif

                    if isSignupMode {
                        TextField("Username (optional)", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .username)
                            .onSubmit {
                                focusedField = .password
                            }
                            #if os(macOS)
                            .frame(maxWidth: 300)
                            #endif
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            if !email.isEmpty && !password.isEmpty && !authManager.isLoading {
                                Task {
                                    if isSignupMode {
                                        await authManager.signup(
                                            email: email,
                                            password: password,
                                            username: username.isEmpty ? nil : username
                                        )
                                    } else {
                                        await authManager.login(email: email, password: password, rememberMe: rememberMe)
                                    }
                                }
                            }
                        }
                        #if os(macOS)
                        .frame(maxWidth: 300)
                        #endif

                    if !isSignupMode {
                        HStack {
                            Toggle(isOn: $rememberMe) {
                                Text("Remember Me")
                                    .font(.footnote)
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #else
                            .toggleStyle(.switch)
                            #endif
                            Spacer()
                        }
                        #if os(macOS)
                        .frame(maxWidth: 300)
                        #endif
                    }
                }
                #if os(iOS)
                .padding(.horizontal)
                #endif

                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                Button(action: {
                    Task {
                        if isSignupMode {
                            await authManager.signup(
                                email: email,
                                password: password,
                                username: username.isEmpty ? nil : username
                            )
                        } else {
                            await authManager.login(email: email, password: password, rememberMe: rememberMe)
                        }
                    }
                }) {
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else {
                        Text(isSignupMode ? "Sign Up" : "Log In")
                    }
                }
                #if os(macOS)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                #else
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                #endif
                .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
                .keyboardShortcut(.defaultAction)
                
                Button(action: {
                    withAnimation {
                        isSignupMode.toggle()
                        authManager.errorMessage = nil
                    }
                }) {
                    Text(isSignupMode ? "Already have an account? Log In" : "Don't have an account? Sign Up")
                        .foregroundColor(.blue)
                        .font(.footnote)
                }
                
                Spacer()
            }
            .padding(.top, 50)
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}