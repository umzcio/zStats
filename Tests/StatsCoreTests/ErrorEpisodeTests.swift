import Testing
@testable import StatsCore

@Test func startupWithoutFailureDoesNotEmitANotification() {
    var tracker = ErrorEpisodeTracker()
    #expect(tracker.notification(for: nil) == nil)
    #expect(tracker.notification(for: nil) == nil)
}

@Test func continuingFailureEmitsOnlyOnceUntilRecovery() {
    var tracker = ErrorEpisodeTracker()

    #expect(tracker.notification(for: "History could not be saved: disk full") == "History could not be saved: disk full")
    // Dismissing the alert does not change the persistence episode.
    #expect(tracker.notification(for: "History could not be saved: disk full") == nil)
    #expect(tracker.notification(for: "History could not be saved: permission denied") == nil)

    #expect(tracker.notification(for: nil) == nil)
    #expect(tracker.notification(for: "History could not be saved: disk full") == "History could not be saved: disk full")
}
