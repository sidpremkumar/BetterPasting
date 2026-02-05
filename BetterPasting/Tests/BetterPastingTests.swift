import Testing
@testable import BetterPasting

@Test func testRelativeTimestampFormatter() async throws {
    let now = Date()

    // Test "Just now"
    let justNow = RelativeTimestampFormatter.format(now)
    #expect(justNow == "Just now")

    // Test minutes ago
    let fiveMinAgo = Date(timeIntervalSinceNow: -300)
    let fiveMinResult = RelativeTimestampFormatter.format(fiveMinAgo)
    #expect(fiveMinResult == "5 min ago")

    // Test hours ago
    let twoHoursAgo = Date(timeIntervalSinceNow: -7200)
    let twoHoursResult = RelativeTimestampFormatter.format(twoHoursAgo)
    #expect(twoHoursResult == "2 hr ago")
}
