import Foundation
import Network
import Combine
import Core

/// Monitors network connectivity status
@MainActor
public class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    
    private var monitor: NetworkPathMonitorProtocol
    private let queue: DispatchQueue
    private let logger = Logger.shared
    
    @Published public private(set) var isConnected = true  // Start with true, assume online
    @Published public private(set) var connectionType: ConnectionType = .unknown
    @Published public private(set) var isExpensive = false
    @Published public private(set) var isConstrained = false
    @Published public private(set) var hasCheckedConnection = false  // Track if we've checked at least once
    
    public enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
        case unavailable
        
        public var displayName: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "Cellular"
            case .wired: return "Wired"
            case .unknown: return "Unknown"
            case .unavailable: return "No Connection"
            }
        }
        
        public var symbolName: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .wired: return "cable.connector"
            case .unknown: return "questionmark.circle"
            case .unavailable: return "wifi.slash"
            }
        }
    }
    
    private init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "NetworkMonitor")
        startMonitoring()
    }
    
    /// Internal initializer for testing with mock monitor
    internal init(monitor: NetworkPathMonitorProtocol, queue: DispatchQueue = DispatchQueue(label: "NetworkMonitor.Test")) {
        self.monitor = monitor
        self.queue = queue
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                self.hasCheckedConnection = true
                
                // Determine connection type
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) {
                        self.connectionType = .wifi
                    } else if path.usesInterfaceType(.cellular) {
                        self.connectionType = .cellular
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        self.connectionType = .wired
                    } else {
                        self.connectionType = .unknown
                    }
                } else {
                    self.connectionType = .unavailable
                }
                
                // Log connection changes
                if wasConnected != self.isConnected {
                    if self.isConnected {
                        self.logger.log("✅ Network connected (\(self.connectionType.displayName))", category: "NetworkMonitor")
                    } else {
                        self.logger.log("❌ Network disconnected", category: "NetworkMonitor")
                    }
                }
                
                // Log connection type changes
                self.logger.debug("Network status: \(self.connectionType.displayName), Expensive: \(self.isExpensive), Constrained: \(self.isConstrained)", category: "NetworkMonitor")
            }
        }
        
        monitor.start(queue: queue)
        logger.log("📡 Network monitoring started", category: "NetworkMonitor")
    }
    
    deinit {
        monitor.cancel()
    }
}