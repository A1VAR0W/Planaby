import Foundation
import Observation
import Security
import SwiftData

/// Cuenta de correo IMAP. La contraseña (de aplicación) va al Llavero, nunca a los ajustes.
struct MailAccount: Codable, Equatable {
    var host: String
    var port = 993
    var username: String
    /// UID más alto ya filtrado, para no volver a mirar los mismos.
    var lastUID = 0

    static let presets: [(name: String, host: String)] = [
        ("Gmail", "imap.gmail.com"),
        ("iCloud", "imap.mail.me.com"),
        ("Outlook / Hotmail", "outlook.office365.com"),
        ("Yahoo", "imap.mail.yahoo.com"),
    ]
}

/// Mira los correos sin leer por IMAP y los pasa por el filtro de mensajes. Se comprueba al abrir
/// la app (como mucho cada 10 minutos), al deslizar en la bandeja o con la acción de Atajos.
@Observable
@MainActor
final class MailInbox {
    static let shared = MailInbox()

    private(set) var account: MailAccount?
    private(set) var isChecking = false
    private(set) var lastCheck: Date?
    private(set) var lastError: String?

    private static let accountKey = "mailAccount"
    private static let keychainService = "com.alvaro.planaby.imap"
    private static let interval: TimeInterval = 10 * 60
    /// Como mucho tantos correos nuevos por comprobación (los más recientes).
    private static let batch = 15

    private init() {
        account = UserDefaults.standard.data(forKey: Self.accountKey)
            .flatMap { try? JSONDecoder().decode(MailAccount.self, from: $0) }
    }

    // MARK: Cuenta

    /// Prueba la conexión y, si va bien, guarda la cuenta.
    func connect(host: String, username: String, password: String) async throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = IMAPClient(host: host, port: 993)
        try await Self.withTimeout(client) {
            try await client.open()
            try await client.login(user: username, password: password)
            await client.logout()
        }
        Self.savePassword(password, for: username)
        save(MailAccount(host: host, username: username))
        lastError = nil
    }

    func disconnect() {
        if let account { Self.deletePassword(for: account.username) }
        account = nil
        lastCheck = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
    }

    private func save(_ account: MailAccount) {
        self.account = account
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Self.accountKey)
        }
    }

    // MARK: Comprobar

    func checkIfNeeded(context: ModelContext) {
        guard account != nil, !isChecking else { return }
        if let lastCheck, Date.now.timeIntervalSince(lastCheck) < Self.interval { return }
        Task { await check(context: context) }
    }

    /// Devuelve cuántos correos nuevos se han filtrado.
    @discardableResult
    func check(context: ModelContext) async -> Int {
        guard var account, !isChecking else { return 0 }
        guard let password = Self.password(for: account.username) else {
            lastError = "Falta la contraseña. Vuelve a conectar la cuenta."
            return 0
        }
        isChecking = true
        defer { isChecking = false }

        let client = IMAPClient(host: account.host, port: account.port)
        var mails: [IMAPClient.Mail] = []
        do {
            let lastUID = account.lastUID
            let username = account.username
            let batch = Self.batch
            mails = try await Self.withTimeout(client) {
                try await client.open()
                try await client.login(user: username, password: password)
                let since = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
                let uids = try await client.unseenUIDs(since: since).filter { $0 > lastUID }.sorted().suffix(batch)
                var fetched: [IMAPClient.Mail] = []
                for uid in uids {
                    if let mail = try await client.fetch(uid: uid) { fetched.append(mail) }
                }
                await client.logout()
                return fetched
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return 0
        }

        var added = 0
        for mail in mails {
            let headers = MailText.headers(mail.header)
            let item = await MessageTriage.ingest(
                source: .mail,
                sender: MailText.senderName(headers["from"] ?? ""),
                subject: headers["subject"] ?? "",
                body: MailText.body(mail.body),
                received: MailText.date(headers["date"]),
                externalID: "\(account.username)|\(mail.uid)",
                context: context
            )
            if item != nil { added += 1 }
        }
        if let highest = mails.map(\.uid).max() { account.lastUID = max(account.lastUID, highest) }
        save(account)
        lastCheck = .now
        return added
    }

    /// Si el servidor no responde en 45 s, se corta la conexión y la espera termina con error.
    private static func withTimeout<T: Sendable>(_ client: IMAPClient, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let watchdog = Task.detached {
            try await Task.sleep(for: .seconds(45))
            client.close()
        }
        defer { watchdog.cancel() }
        return try await work()
    }

    // MARK: Llavero

    private static func query(for username: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: username]
    }

    private static func savePassword(_ password: String, for username: String) {
        SecItemDelete(query(for: username) as CFDictionary)
        var item = query(for: username)
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func password(for username: String) -> String? {
        var request = query(for: username)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deletePassword(for username: String) {
        SecItemDelete(query(for: username) as CFDictionary)
    }
}
