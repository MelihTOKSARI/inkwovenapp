import Foundation
import OSLog
import Security

/// The few values that must not sit in UserDefaults, where they land in the
/// app's Preferences plist and in every unencrypted device backup. Small on
/// purpose: this is a storage detail, not an abstraction.
enum InkKeychain {
    private static let log = Logger(subsystem: "com.empath.inkwoven", category: "keychain")
    private static let service = "com.empath.inkwoven"

    static func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                log.error("keychain read failed (\(status, privacy: .public))")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        var item = baseQuery(account: account)
        SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = data
        // AfterFirstUnlock so a background refresh can still read it;
        // ThisDeviceOnly keeps the identity out of backups and off any device
        // it might be restored to.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("keychain write failed (\(status, privacy: .public))")
            return false
        }
        return true
    }

    static func remove(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
