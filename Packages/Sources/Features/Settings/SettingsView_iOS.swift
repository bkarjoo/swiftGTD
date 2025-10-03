#if os(iOS)
import SwiftUI
import Core
import Services

public struct SettingsView_iOS: View {
    public init() {}
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("apiURL") private var apiURL = "http://localhost:8000"
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4
    @State private var showingLogoutAlert = false
    
    
    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account")) {
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
                
                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $darkMode)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tree Font Size")
                            Spacer()
                            Text("\(treeFontSize)pt")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: Binding(
                            get: { Double(treeFontSize) },
                            set: { treeFontSize = Int($0) }
                        ), in: 8...32, step: 1)

                        if treeFontSize < 12 || treeFontSize > 18 {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("12-18pt is ideal for readability")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Line Spacing")
                            Spacer()
                            Text("\(treeLineSpacing)pt")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: Binding(
                            get: { Double(treeLineSpacing) },
                            set: { treeLineSpacing = Int($0) }
                        ), in: 0...20, step: 1)

                        if treeLineSpacing < 2 || treeLineSpacing > 8 {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("2-8pt is ideal for spacing")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Data Management")) {
                    NavigationLink(destination: TagManagementView()) {
                        HStack {
                            Image(systemName: "tag.circle.fill")
                                .foregroundColor(.blue)
                            Text("Manage Tags")
                        }
                    }
                }

                Section(header: Text("API Settings")) {
                    HStack {
                        Text("API URL")
                        Spacer()
                        Text(apiURL)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("GitHub Repository", destination: URL(string: "https://github.com/yourusername/swiftgtd")!)
                    
                    Link("Report an Issue", destination: URL(string: "https://github.com/yourusername/swiftgtd/issues")!)
                }
            }
            .navigationTitle("Settings")
            .alert("Log Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    authManager.logout()
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
    }
}

#Preview {
    SettingsView_iOS()
        .environmentObject(AuthManager())
}
#endif