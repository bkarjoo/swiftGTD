import SwiftUI
import Services

/// Visual indicator for network connection status
public struct NetworkStatusIndicator: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var offlineQueue = OfflineQueueManager.shared
    @State private var showingDetails = false
    let lastSyncDate: Date?
    
    public init(lastSyncDate: Date? = nil) {
        self.lastSyncDate = lastSyncDate
    }
    
    public var body: some View {
        Button(action: {
            showingDetails.toggle()
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(networkMonitor.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Image(systemName: networkMonitor.connectionType.symbolName)
                    .font(.system(size: 12))
                    .foregroundColor(networkMonitor.isConnected ? .green : .red)
                
                // Show pending sync indicator
                if !offlineQueue.pendingOperations.isEmpty || offlineQueue.isSyncing {
                    if offlineQueue.isSyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        // Show count of pending operations
                        Text("\(offlineQueue.pendingOperations.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Circle().fill(Color.orange))
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help(connectionStatusText)
        .popover(isPresented: $showingDetails) {
            NetworkDetailsView(lastSyncDate: lastSyncDate)
        }
    }
    
    private var connectionStatusText: String {
        if networkMonitor.isConnected {
            var status = "Connected via \(networkMonitor.connectionType.displayName)"
            if networkMonitor.isExpensive {
                status += " (Expensive)"
            }
            if networkMonitor.isConstrained {
                status += " (Constrained)"
            }
            return status
        } else {
            if lastSyncDate != nil {
                return "Offline - Using cached data"
            } else {
                return "No Internet Connection"
            }
        }
    }
}

/// Detailed network information view
private struct NetworkDetailsView: View {
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var offlineQueue = OfflineQueueManager.shared
    let lastSyncDate: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Status")
                .font(.headline)
            
            Divider()
            
            HStack {
                Text("Connection:")
                Spacer()
                Text(networkMonitor.isConnected ? "Online" : "Offline")
                    .foregroundColor(networkMonitor.isConnected ? .green : .red)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Text("Type:")
                Spacer()
                Label(networkMonitor.connectionType.displayName, 
                      systemImage: networkMonitor.connectionType.symbolName)
            }
            
            if networkMonitor.isConnected {
                HStack {
                    Text("Expensive:")
                    Spacer()
                    Text(networkMonitor.isExpensive ? "Yes" : "No")
                        .foregroundColor(networkMonitor.isExpensive ? .orange : .secondary)
                }
                
                HStack {
                    Text("Constrained:")
                    Spacer()
                    Text(networkMonitor.isConstrained ? "Yes" : "No")
                        .foregroundColor(networkMonitor.isConstrained ? .orange : .secondary)
                }
                
                if networkMonitor.isExpensive || networkMonitor.isConstrained {
                    Text("Data usage may be limited or costly")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            } else {
                Text("SwiftGTD is operating in offline mode. Changes will be synced when connection is restored.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                if let syncDate = lastSyncDate {
                    HStack {
                        Text("Last sync:")
                        Spacer()
                        Text(syncDate, style: .relative)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .padding(.top, 2)
                }
            }
            
            // Show pending operations
            if !offlineQueue.pendingOperations.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Pending Changes", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        
                        if offlineQueue.isSyncing {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    
                    Text(offlineQueue.getPendingSummary())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(offlineQueue.isSyncing ? "Syncing now..." :
                         (networkMonitor.isConnected ? "Syncing automatically..." : "Will sync when connection is restored"))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Debug buttons
                    HStack {
                        Button("Force Sync") {
                            Task {
                                let result = await offlineQueue.processPendingOperations()
                                print("Sync result: \(result)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button("Clear Queue") {
                            Task {
                                await offlineQueue.clearQueue()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}