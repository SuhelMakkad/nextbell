import XCTest
@testable import nextbell_platform

final class RunnerTests: XCTestCase {
    @MainActor func testNativeActionLedgerSurvivesAcknowledgementOfOtherActions() throws {
        let one = UUID().uuidString
        let two = UUID().uuidString
        NextbellAlarmEngine.record(one, kind: "dismiss")
        NextbellAlarmEngine.record(two, kind: "snooze")
        let ours = NextbellAlarmEngine.pendingActions().filter { $0.alarmId == one || $0.alarmId == two }
        XCTAssertEqual(ours.count, 2)
        NextbellAlarmEngine.acknowledge(ours.filter { $0.alarmId == one }.map { $0.id })
        let remaining = NextbellAlarmEngine.pendingActions().filter { $0.alarmId == one || $0.alarmId == two }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.kind, "snooze")
        NextbellAlarmEngine.acknowledge(remaining.map { $0.id })
    }
}
