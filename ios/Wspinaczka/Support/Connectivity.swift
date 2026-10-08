import Foundation
import Network
import Observation

/// Whether the device has a usable network path. Only a hint: a request can
/// still fail with a path, and the outbox retries regardless.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "wspinaczka.connectivity", qos: .utility))
    }

    private func update(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
    }
}

extension Error {
    /// The request never reached the server (or its answer never came back);
    /// worth retrying once the network is back.
    var isConnectivityError: Bool {
        guard let urlError = self as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
             .callIsActive, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
