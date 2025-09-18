#if os(macOS)
import SwiftUI
import Core
import Services

public struct SettingsView_macOS: View {
    public init() {}
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("apiURL") private var apiURL = "http://localhost:8000"
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4
    @State private var showingLogoutAlert = false
    
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GroupBox(label: Text("Account").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let user = authManager.currentUser {
                            HStack {
                                Text("Email")
                                Spacer()
                                Text(user.email)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let fullName = user.fullName {
                                HStack {
                                    Text("Name")
                                    Spacer()
                                    Text(fullName)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Button(action: {
                            showingLogoutAlert = true
                        }) {
                            Text("Log Out")
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                GroupBox(label: Text("Appearance").font(.headline)) {
                    VStack(alignment: .leading, spacing: 15) {
                        Toggle("Dark Mode", isOn: $darkMode)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Tree Font Size")
                                Spacer()
                                Text("\(treeFontSize)pt")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }

                            Slider(value: Binding(
                                get: { Double(treeFontSize) },
                                set: { treeFontSize = Int($0) }
                            ), in: 8...32, step: 1)
                                .frame(maxWidth: 400)

                            if treeFontSize < 12 || treeFontSize > 18 {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("12-18pt is ideal for readability")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Line Spacing")
                                Spacer()
                                Text("\(treeLineSpacing)pt")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }

                            Slider(value: Binding(
                                get: { Double(treeLineSpacing) },
                                set: { treeLineSpacing = Int($0) }
                            ), in: 0...20, step: 1)
                                .frame(maxWidth: 400)

                            if treeLineSpacing < 2 || treeLineSpacing > 8 {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("2-8pt is ideal for spacing")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                GroupBox(label: Text("API Settings").font(.headline)) {
                    HStack {
                        Text("API URL")
                        Spacer()
                        Text(apiURL)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical, 5)
                }
                
                GroupBox(label: Text("About").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.secondary)
                        }
                        
                        Link("GitHub Repository", destination: URL(string: "https://github.com/yourusername/swiftgtd")!)
                        
                        Link("Report an Issue", destination: URL(string: "https://github.com/yourusername/swiftgtd/issues")!)
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Settings")
        .alert("Log Out", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                authManager.logout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .preferredColorScheme(darkMode ? .dark : .light)
    }
}

#Preview {
    SettingsView_macOS()
        .environmentObject(AuthManager())
}
#endif