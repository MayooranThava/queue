import Foundation

enum QueueEntitlement: String, Sendable {
    case pro
}

/// Isolates monetization. Free defaults until StoreKit 2 is wired.
protocol EntitlementService: Sendable {
    func isEntitled(to entitlement: QueueEntitlement) -> Bool
}

struct FreeEntitlementService: EntitlementService {
    func isEntitled(to entitlement: QueueEntitlement) -> Bool {
        false
    }
}
