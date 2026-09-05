import AlarmKit
import AppIntents
import Foundation
import SwiftUI

struct NextbellMetadata: AlarmMetadata { var entryID: String }

private struct SavedAlarm: Codable {
    var id: String; var entryId: String; var title: String; var subtitle: String
    var fireAtMillis: Int64; var snoozeMinutes: Int64; var sourceIds: [String]; var parentId: String?
    init(_ a: NativeAlarm) {
        id = a.id; entryId = a.entryId; title = a.title; subtitle = a.subtitle
        fireAtMillis = a.fireAtMillis; snoozeMinutes = a.snoozeMinutes; sourceIds = a.sourceIds; parentId = a.parentId
    }
    var native: NativeAlarm { NativeAlarm(id: id, entryId: entryId, title: title, subtitle: subtitle,
        fireAtMillis: fireAtMillis, snoozeMinutes: snoozeMinutes, sourceIds: sourceIds, parentId: parentId, ringing: false) }
}
private struct SavedAction: Codable { var id: String; var alarmId: String; var kind: String; var atMillis: Int64 }

@MainActor
enum NextbellAlarmEngine {
    private static let defaults = UserDefaults.standard
    private static var saved: [SavedAlarm] {
        get { (try? JSONDecoder().decode([SavedAlarm].self, from: defaults.data(forKey: "nextbell.alarms") ?? Data())) ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "nextbell.alarms") }
    }
    private static var actions: [SavedAction] {
        get { (try? JSONDecoder().decode([SavedAction].self, from: defaults.data(forKey: "nextbell.actions") ?? Data())) ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "nextbell.actions") }
    }
    static func record(_ id: String, kind: String) {
        defaults.set(true, forKey: "nextbell.handled.\(id)")
        var list = actions
        list.append(SavedAction(id: UUID().uuidString, alarmId: id, kind: kind, atMillis: Int64(Date().timeIntervalSince1970 * 1000)))
        actions = list
    }
    static func pendingActions() -> [NativeAlarmAction] {
        actions.map { NativeAlarmAction(id: $0.id, alarmId: $0.alarmId, kind: $0.kind, atMillis: $0.atMillis) }
    }
    static func acknowledge(_ ids: [String]) { actions = actions.filter { !ids.contains($0.id) } }
    static func schedule(_ a: NativeAlarm) async throws {
        guard !defaults.bool(forKey: "nextbell.handled.\(a.id)") else {
            throw PigeonError(code: "handled", message: "This reminder was already handled.", details: nil)
        }
        guard AlarmManager.shared.authorizationState == .authorized else {
            throw PigeonError(code: "permission", message: "Allow Nextbell alarms in Settings.", details: nil)
        }
        guard let id = UUID(uuidString: a.id), Double(a.fireAtMillis) / 1000 > Date().timeIntervalSince1970 else {
            throw PigeonError(code: "expired", message: "This alarm time has passed.", details: nil)
        }
        let stop = AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "xmark")
        let snooze = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: a.title),
                secondaryButton: snooze, secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: a.title),
                stopButton: stop, secondaryButton: snooze, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
            metadata: NextbellMetadata(entryID: a.entryId), tintColor: Color.indigo)
        let config = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(Date(timeIntervalSince1970: Double(a.fireAtMillis) / 1000)),
            attributes: attributes, stopIntent: DismissNextbellAlarm(alarmID: a.id),
            secondaryIntent: SnoozeNextbellAlarm(alarmID: a.id))
        do {
            // Scheduling the same ID replaces an existing alarm without creating duplicates.
            _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
            var list = saved.filter { $0.id != a.id }; list.append(SavedAlarm(a)); saved = list
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw PigeonError(code: "capacity", message: "The device alarm limit has been reached.", details: nil)
        }
    }
    static func cancel(_ ids: [String]) throws {
        let active = Set(try AlarmManager.shared.alarms.map { $0.id.uuidString.lowercased() })
        for value in ids {
            if let id = UUID(uuidString: value), active.contains(value.lowercased()) {
                try AlarmManager.shared.cancel(id: id)
            }
            saved = saved.filter { $0.id != value }
        }
    }
    static func all() throws -> [NativeAlarm] {
        let actual = Dictionary(uniqueKeysWithValues: try AlarmManager.shared.alarms.map { ($0.id.uuidString.lowercased(), $0) })
        var result: [NativeAlarm] = []
        for stored in saved {
            if let alarm = actual[stored.id.lowercased()] {
                var native = stored.native
                native.ringing = alarm.state == .alerting
                result.append(native)
            } else if Double(stored.fireAtMillis) / 1000 <= Date().timeIntervalSince1970 {
                record(stored.parentId ?? stored.id, kind: "handled")
                saved = saved.filter { $0.id != stored.id }
            }
            // Future alarms absent from the OS are omitted so Dart can repair them.
        }
        return result
    }
    static func handle(_ id: String, snooze: Bool) async throws {
        guard let alarm = saved.first(where: { $0.id == id }) else { return }
        if snooze {
            var next = alarm.native
            next.id = UUID().uuidString.lowercased(); next.parentId = alarm.parentId ?? alarm.id
            next.subtitle = "Snoozed reminder"
            next.fireAtMillis = Int64(Date().timeIntervalSince1970 * 1000) + alarm.snoozeMinutes * 60_000
            try await schedule(next)
        }
        record(alarm.parentId ?? alarm.id, kind: snooze ? "snooze" : "dismiss")
        try cancel([id])
    }
}

public struct DismissNextbellAlarm: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Dismiss Nextbell alarm"
    public static var openAppWhenRun = false
    @Parameter(title: "Alarm ID") public var alarmID: String
    public init() {}
    public init(alarmID: String) { self.alarmID = alarmID }
    public func perform() async throws -> some IntentResult {
        try await NextbellAlarmEngine.handle(alarmID, snooze: false)
        return .result()
    }
}
public struct SnoozeNextbellAlarm: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Snooze Nextbell alarm"
    public static var openAppWhenRun = false
    @Parameter(title: "Alarm ID") public var alarmID: String
    public init() {}
    public init(alarmID: String) { self.alarmID = alarmID }
    public func perform() async throws -> some IntentResult {
        try await NextbellAlarmEngine.handle(alarmID, snooze: true)
        return .result()
    }
}
