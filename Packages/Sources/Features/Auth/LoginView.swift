import SwiftUI
import Core
import Services

public struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isSignupMode = false
    @State private var username = ""
    
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
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                    
                    if isSignupMode {
                        TextField("Username (optional)", text: $username)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
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
                            await authManager.login(email: email, password: password)
                        }
                    }
                }) {
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(isSignupMode ? "Sign Up" : "Log In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
                
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