import Foundation

public protocol SleepPowerControlling {
    func isSleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
}

public protocol SleepRecoveryStoring {
    func needsRecovery() throws -> Bool
    func setNeedsRecovery(_ value: Bool) throws
}

/// Accessed only on the helper's serial queue. Each authenticated XPC connection owns a lease.
public final class SleepLeaseCoordinator {
    private let power: any SleepPowerControlling
    private let recovery: any SleepRecoveryStoring
    private var leases: [UUID: Lease] = [:]
    private var ownsSetting = false
    private struct Lease { let deadline: Date? }

    public init(power: any SleepPowerControlling, recovery: any SleepRecoveryStoring) throws {
        self.power = power
        self.recovery = recovery
        ownsSetting = try recovery.needsRecovery()
    }

    public var nextDeadline: Date? { leases.values.compactMap(\.deadline).min() }
    public var needsRestoreRetry: Bool { leases.isEmpty && ownsSetting }

    public func set(_ enabled: Bool, owner: UUID, deadline: Date?, now: Date = Date()) throws {
        if enabled, deadline == nil || deadline! > now {
            if !(try power.isSleepDisabled()) {
                // Persist ownership before touching the system so a daemon restart can recover.
                try recovery.setNeedsRecovery(true)
                ownsSetting = true
                do { try power.setSleepDisabled(true) }
                catch {
                    if leases.isEmpty { try? restoreIfUnused() }
                    throw error
                }
            }
            leases[owner] = Lease(deadline: deadline)
        } else {
            leases.removeValue(forKey: owner)
            try restoreIfUnused()
        }
    }

    public func disconnect(_ owner: UUID) throws {
        leases.removeValue(forKey: owner)
        try restoreIfUnused()
    }

    public func expire(now: Date = Date()) throws {
        leases = leases.filter { $0.value.deadline.map { $0 > now } ?? true }
        try restoreIfUnused()
    }

    public func shutdown() throws {
        leases.removeAll()
        try restoreIfUnused()
    }

    public func restoreLegacySetting() throws {
        // Only an authenticated app calls this when migrating its old managed setting.
        if try power.isSleepDisabled() {
            try recovery.setNeedsRecovery(true)
            ownsSetting = true
        }
        try restoreIfUnused()
    }

    private func restoreIfUnused() throws {
        guard leases.isEmpty, ownsSetting else { return }
        try power.setSleepDisabled(false)
        try recovery.setNeedsRecovery(false)
        ownsSetting = false
    }
}
