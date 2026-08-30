import Foundation

/// A non-persistent UserDefaults implementation for diagnostics and tests.
/// It deliberately never creates a CFPreferences domain or a plist on disk.
final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var values: [String: Any] = [:]
    private var registeredValues: [String: Any] = [:]

    init(memory: Void = ()) {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock {
            values[defaultName] ?? registeredValues[defaultName]
        }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        _ = lock.withLock {
            if let value {
                values[defaultName] = value
            } else {
                values.removeValue(forKey: defaultName)
            }
        }
    }

    override func removeObject(forKey defaultName: String) {
        _ = lock.withLock {
            values.removeValue(forKey: defaultName)
        }
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        lock.withLock {
            registeredValues.merge(registrationDictionary) { current, _ in current }
        }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock {
            registeredValues.merging(values) { _, explicit in explicit }
        }
    }

    override func synchronize() -> Bool {
        true
    }
}
