import Foundation
import Network
import Combine

// MARK: - Network Monitor Protocol
protocol NetworkMonitorProtocol: AnyObject, Sendable {
    var isConnected: Bool { get }
    var connectionType: NWInterface.InterfaceType? { get }
    
    func startMonitoring()
    func stopMonitoring()
    func onConnectivityChange(_ handler: @escaping @Sendable (Bool) -> Void) async
}

// MARK: - Network Monitor Implementation
actor NetworkMonitor: NetworkMonitorProtocol {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.voicenote.networkmonitor")
    private var connectivityHandlers: [@Sendable (Bool) -> Void] = []
    
    nonisolated let isConnectedPublisher = CurrentValueSubject<Bool, Never>(false)
    
    private var _isConnected: Bool = false
    private var _connectionType: NWInterface.InterfaceType?
    
    nonisolated var isConnected: Bool {
        isConnectedPublisher.value
    }
    
    nonisolated var connectionType: NWInterface.InterfaceType? {
        // For now, return nil - can be improved with AsyncStream if needed
        nil
    }
    
    init() {
        Task {
            await setupMonitor()
        }
    }
    
    deinit {
        monitor.cancel()
    }
    
    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.updatePath(path)
            }
        }
    }
    
    private func updatePath(_ path: NWPath) {
        let wasConnected = _isConnected
        _isConnected = path.status == .satisfied
        _connectionType = path.availableInterfaces.first?.type
        
        // Update publisher
        isConnectedPublisher.send(_isConnected)
        
        if wasConnected != _isConnected {
            Task {
                await notifyHandlers(_isConnected)
            }
        }
    }
    
    nonisolated func startMonitoring() {
        monitor.start(queue: queue)
    }
    
    nonisolated func stopMonitoring() {
        monitor.cancel()
    }
    
    func onConnectivityChange(_ handler: @escaping @Sendable (Bool) -> Void) async {
        connectivityHandlers.append(handler)
    }
    
    private func notifyHandlers(_ isConnected: Bool) async {
        for handler in connectivityHandlers {
            Task { @MainActor in
                handler(isConnected)
            }
        }
    }
}