#if os(macOS)
import SwiftUI
import Core
import Services
import Networking
import Models

public struct SettingsView_macOS: View {
    public init() {}
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("apiURL") private var apiURL = "http://localhost:8000"
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4
    @State private var showingLogoutAlert = false
    @State private var defaultNodeId: String?
    @State private var availableFolders: [Node] = []
    @State private var isLoadingFolders = false

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

                GroupBox(label: Text("Default Folder").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Select a default folder for quick task creation (press Q key)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Picker("Default Folder", selection: $defaultNodeId) {
                                Text("No default folder")
                                    .tag(nil as String?)

                                ForEach(availableFolders, id: \.id) { folder in
                                    Text(folder.title)
                                        .tag(folder.id as String?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: 300)
                            .disabled(isLoadingFolders)

                            if isLoadingFolders {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        }

                        if let selectedId = defaultNodeId,
                           let selectedFolder = availableFolders.first(where: { $0.id == selectedId }) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text("Quick-add (Q key) will create tasks in \"\(selectedFolder.title)\"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
                .onChange(of: defaultNodeId) { newValue in
                    Task {
                        await saveDefaultNode(newValue)
                    }
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
        .onAppear {
            Task {
                await loadFoldersAndDefault()
            }
        }
    }

    private func loadFoldersAndDefault() async {
        isLoadingFolders = true
        defer { isLoadingFolders = false }

        do {
            // Load all nodes and filter for folders
            let allNodes = try await APIClient.shared.getAllNodes()
            availableFolders = allNodes.filter { $0.nodeType == "folder" }
                .sorted { $0.title < $1.title }

            // Load current default node
            if let defaultId = try await APIClient.shared.getDefaultNode() {
                defaultNodeId = defaultId
            }
        } catch {
            print("Failed to load folders or default node: \(error)")
        }
    }

    private func saveDefaultNode(_ nodeId: String?) async {
        do {
            try await APIClient.shared.setDefaultNode(nodeId: nodeId)
        } catch {
            print("Failed to save default node: \(error)")
        }
    }
}

#Preview {
    SettingsView_macOS()
        .environmentObject(AuthManager())
}
#endif