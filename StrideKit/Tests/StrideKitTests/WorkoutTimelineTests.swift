import Foundation
import Testing
@testable import StrideKit

@Suite struct WorkoutTimelineTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(_ seconds: TimeInterval, segment: Int) -> RoutePoint {
        RoutePoint(latitude: 0, longitude: 0, altitude: 0, timestamp: t0.addingTimeInterval(seconds), segment: segment)
    }

    @Test func pausesBetweenSegmentsComeOff() {
        // 10 min moving, a 5 min pause after the first 5 min.
        let route = [point(0, segment: 0), point(300, segment: 0), point(600, segment: 1), point(900, segment: 1)]
        let timeline = WorkoutTimeline(start: t0, duration: 600, route: route, now: t0.addingTimeInterval(3_600))
        #expect(timeline.pauses == [DateInterval(start: t0.addingTimeInterval(300), end: t0.addingTimeInterval(600))])
        #expect(timeline.end == t0.addingTimeInterval(900))
        #expect(timeline.movingTime == 600)
    }

    @Test func pauseBeforeTheFirstFixComesOffToo() {
        // Auto-paused at the start line for 2 min: the first fix comes at 2:00, then 10 min of running.
        let route = [point(120, segment: 1), point(720, segment: 1)]
        let timeline = WorkoutTimeline(start: t0, duration: 600, route: route, now: t0.addingTimeInterval(3_600))
        #expect(timeline.end == t0.addingTimeInterval(720))
        #expect(abs(timeline.movingTime - 600) < 0.001)
    }

    @Test func runLoggedNowDoesntEndInTheFuture() {
        let now = t0.addingTimeInterval(60)
        let timeline = WorkoutTimeline(start: t0, duration: 1_800, route: [], now: now)
        #expect(timeline.end == now)
        #expect(timeline.movingTime == 1_800)
    }
}
