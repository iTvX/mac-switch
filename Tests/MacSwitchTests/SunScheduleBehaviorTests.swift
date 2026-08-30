import CoreLocation
import XCTest
@testable import MacSwitch

@MainActor
final class SunScheduleBehaviorTests: XCTestCase {
    func testFreshCacheRequiresRecentCoordinateInCurrentTimeZone() {
        let defaults = InMemoryUserDefaults()
        let provider = SunScheduleProvider(defaults: defaults)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        provider.storeCoordinate(
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
            updatedAt: now.addingTimeInterval(-60),
            timeZone: zone
        )

        XCTAssertFalse(provider.isCacheStale(at: now, timeZone: zone))
        XCTAssertTrue(
            provider.isCacheStale(
                at: now,
                timeZone: TimeZone(identifier: "Asia/Tokyo")!
            )
        )
    }

    func testExpiredOrFutureDatedCacheIsStale() {
        let defaults = InMemoryUserDefaults()
        let provider = SunScheduleProvider(defaults: defaults)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let coordinate = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

        provider.storeCoordinate(
            coordinate,
            updatedAt: now.addingTimeInterval(-SunScheduleProvider.cacheLifetime - 1)
        )
        XCTAssertTrue(provider.isCacheStale(at: now))

        provider.storeCoordinate(coordinate, updatedAt: now.addingTimeInterval(60))
        XCTAssertTrue(provider.isCacheStale(at: now))
    }

    func testInvalidCoordinateIsNeverUsedForSolarCalculations() {
        let defaults = InMemoryUserDefaults()
        let provider = SunScheduleProvider(defaults: defaults)
        provider.storeCoordinate(
            CLLocationCoordinate2D(latitude: 200, longitude: -118),
            updatedAt: Date()
        )

        XCTAssertNil(provider.cachedCoordinate)
        XCTAssertNil(provider.sunWindow())
    }
}
