import Foundation
import Network

/// Protocol for network path monitoring to enable testing
public protocol NetworkPathMonitorProtocol {
    func start(queue: DispatchQueue)
    func cancel()
    var pathUpdateHandler: ((NWPath) -> Void)? { get set }
}

/// Make NWPathMonitor conform to our protocol
extension NWPathMonitor: NetworkPathMonitorProtocol {}

/// Protocol for NetworkMonitor to enable testing
@MainActor
public protocol NetworkMonitorProtocol: AnyObject {
    var isConnected: Bool { get }
    var connectionType: NetworkMonitor.ConnectionType { get }
    var isExpensive: Bool { get }
    var isConstrained: Bool { get }
    var hasCheckedConnection: Bool { get }
}

/// Make NetworkMonitor conform to the protocol
extension NetworkMonitor: NetworkMonitorProtocol {}