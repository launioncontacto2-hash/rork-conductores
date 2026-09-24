import Foundation

public extension Notification.Name {
    static let uberTestSessionTerminated = Notification.Name("UberTest.sessionTerminated")
}

public enum UberTestSessionError: Error, Equatable {
    case terminated
}

@inline(__always)
public func uberTestNotifySessionTerminated() {
    NotificationCenter.default.post(name: .uberTestSessionTerminated, object: nil)
}
