import Flutter
import UIKit
import AlarmKit
import GoogleSignIn
import Security
import UserNotifications

private enum AccountVault {
    private static let service = "com.suhel.nextbell.google"
    static func store(_ user: GIDGoogleUser) throws {
        guard let id = user.userID else { throw PigeonError(code: "account", message: "Google did not return an account ID.", details: nil) }
        let data = try NSKeyedArchiver.archivedData(withRootObject: user, requiringSecureCoding: true)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: id]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PigeonError(code: "keychain", message: "Could not securely save this account.", details: nil) }
    }
    static func users() throws -> [GIDGoogleUser] {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnData as String: true]
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw PigeonError(code: "keychain", message: "Unlock your phone to restore accounts.", details: nil) }
        return try (item as? [Data] ?? []).compactMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: GIDGoogleUser.self, from: $0) }
    }
    static func remove(_ id: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: id] as CFDictionary)
    }
}

@MainActor
public class NextbellPlatformPlugin: NSObject, FlutterPlugin, NextbellHostApi {
    private static var generations: [String: Int] = [:]
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Exclude this app's local cache, settings and native schedule ledger from backup.
        for directory in [FileManager.SearchPathDirectory.libraryDirectory, .documentDirectory] {
            if var url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
            }
        }
        let instance = NextbellPlatformPlugin()
        NextbellHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        registrar.addApplicationDelegate(instance)
    }
    public static func handleURL(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Self.handleURL(url)
    }
    func connect(clientId: String, accountId: String?) async throws -> NativeAccount {
        guard !clientId.isEmpty else { throw PigeonError(code: "configuration", message: "Configure the iOS OAuth client first.", details: nil) }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
            var root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            throw PigeonError(code: "foreground", message: "Open Nextbell to connect Google.", details: nil)
        }
        while let presented = root.presentedViewController { root = presented }
        let previous = try AccountVault.users().first(where: { $0.userID == accountId })
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        // Retained accounts live in separate Keychain entries, independent of SDK currentUser.
        GIDSignIn.sharedInstance.signOut()
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root, hint: previous?.profile?.email,
            additionalScopes: ["https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/tasks"])
        guard accountId == nil || accountId == result.user.userID else {
            throw PigeonError(code: "wrong_account", message: "Choose the original account when reconnecting.", details: nil)
        }
        try AccountVault.store(result.user)
        if let id = result.user.userID { Self.generations[id, default: 0] += 1 }
        return native(result.user)
    }
    private func native(_ user: GIDGoogleUser) -> NativeAccount {
        NativeAccount(id: user.userID ?? "", email: user.profile?.email ?? "", name: user.profile?.name ?? "Google account")
    }
    func accounts() async throws -> [NativeAccount] { try AccountVault.users().map(native) }
    func accessToken(accountId: String) async throws -> String {
        let generation = Self.generations[accountId, default: 0]
        guard let user = try AccountVault.users().first(where: { $0.userID == accountId }) else {
            throw PigeonError(code: "reauthorize", message: "Reconnect this Google account.", details: nil)
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        guard Self.generations[accountId, default: 0] == generation else {
            throw PigeonError(code: "reauthorize", message: "This account connection changed.", details: nil)
        }
        try AccountVault.store(refreshed)
        return refreshed.accessToken.tokenString
    }
    func removeAccount(accountId: String) async throws {
        Self.generations[accountId, default: 0] += 1
        AccountVault.remove(accountId)
        if GIDSignIn.sharedInstance.currentUser?.userID == accountId { GIDSignIn.sharedInstance.signOut() }
    }
    func permissions() async throws -> NativePermissions {
        // AlarmKit authorization is independent of notification authorization.
        let authorized = AlarmManager.shared.authorizationState == .authorized
        return NativePermissions(alarms: authorized, notifications: authorized, fullScreen: authorized)
    }
    func requestPermissions() async throws -> NativePermissions {
        _ = try await AlarmManager.shared.requestAuthorization()
        return try await permissions()
    }
    func openSettings(section: String) async throws {
        if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
    }
    func scheduleAlarm(alarm: NativeAlarm) async throws { try await NextbellAlarmEngine.schedule(alarm) }
    func cancelAlarms(ids: [String]) async throws { try NextbellAlarmEngine.cancel(ids) }
    func alarms() async throws -> [NativeAlarm] { try NextbellAlarmEngine.all() }
    func pendingActions() async throws -> [NativeAlarmAction] { NextbellAlarmEngine.pendingActions() }
    func acknowledgeActions(ids: [String]) async throws { NextbellAlarmEngine.acknowledge(ids) }
}
