import Foundation
import Network

enum IMAPError: LocalizedError {
    case closed
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .closed:
            "Se cortó la conexión con el servidor de correo."
        case .rejected(let reason):
            reason.localizedCaseInsensitiveContains("auth") || reason.localizedCaseInsensitiveContains("login")
                ? "El servidor no acepta el usuario o la contraseña. Usa una contraseña de aplicación."
                : "El servidor de correo respondió: \(reason.prefix(120))"
        }
    }
}

/// Cliente IMAP mínimo (TLS, puerto 993): lo justo para leer los correos sin abrir de la bandeja
/// de entrada sin marcarlos como leídos. Se usa desde una sola tarea cada vez.
final class IMAPClient: @unchecked Sendable {
    struct Response {
        var line = ""
        var literals: [Data] = []
    }

    struct Mail: Sendable {
        let uid: Int
        let header: Data
        let body: Data
    }

    private let connection: NWConnection
    private var buffer = Data()
    private var counter = 0

    init(host: String, port: Int) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? .imaps,
            using: NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp)
        )
    }

    func open() async throws {
        try await Self.start(connection)
        _ = try await readResponse()
    }

    /// Corta la conexión (también sirve para abortar una espera desde otra tarea).
    func close() {
        connection.cancel()
    }

    func login(user: String, password: String) async throws {
        try await run("LOGIN \(Self.quoted(user)) \(Self.quoted(password))")
    }

    /// UIDs sin leer de la bandeja de entrada desde una fecha.
    func unseenUIDs(since date: Date) async throws -> [Int] {
        try await run("SELECT INBOX")
        let day = Self.searchDate.string(from: date)
        let responses = try await run("UID SEARCH UNSEEN SINCE \(day)")
        return responses
            .filter { $0.line.hasPrefix("* SEARCH") }
            .flatMap { $0.line.dropFirst(8).split(separator: " ").compactMap { Int($0) } }
    }

    /// Cabeceras y el comienzo del texto, sin marcar como leído (BODY.PEEK).
    func fetch(uid: Int) async throws -> Mail? {
        let responses = try await run("UID FETCH \(uid) (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)] BODY.PEEK[1]<0.2000>)")
        guard let response = responses.first(where: { $0.line.contains("FETCH") && !$0.literals.isEmpty }) else { return nil }
        return Mail(uid: uid, header: response.literals[0], body: response.literals.count > 1 ? response.literals[1] : Data())
    }

    func logout() async {
        _ = try? await run("LOGOUT")
        close()
    }

    // MARK: Protocolo

    @discardableResult
    private func run(_ command: String) async throws -> [Response] {
        counter += 1
        let tag = "A\(counter)"
        try await Self.send(Data("\(tag) \(command)\r\n".utf8), on: connection)
        var responses: [Response] = []
        while true {
            let response = try await readResponse()
            if response.line.hasPrefix(tag + " ") {
                let status = String(response.line.dropFirst(tag.count + 1))
                guard status.hasPrefix("OK") else { throw IMAPError.rejected(status) }
                return responses
            }
            responses.append(response)
        }
    }

    /// Una respuesta completa: sus líneas y los literales {n} que traiga.
    private func readResponse() async throws -> Response {
        var response = Response()
        while true {
            let line = String(decoding: try await readLine(), as: UTF8.self)
            response.line += line
            guard let size = Self.literalSize(line) else { return response }
            response.literals.append(try await read(count: size))
        }
    }

    private func readLine() async throws -> Data {
        let separator = Data("\r\n".utf8)
        while true {
            if let range = buffer.range(of: separator) {
                let line = Data(buffer[buffer.startIndex..<range.lowerBound])
                buffer = Data(buffer[range.upperBound...])
                return line
            }
            buffer.append(try await Self.receive(on: connection))
        }
    }

    private func read(count: Int) async throws -> Data {
        while buffer.count < count {
            buffer.append(try await Self.receive(on: connection))
        }
        let chunk = Data(buffer.prefix(count))
        buffer = Data(buffer.dropFirst(count))
        return chunk
    }

    static func literalSize(_ line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        return Int(line[line.index(after: open)..<line.index(before: line.endIndex)])
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static let searchDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-MMM-yyyy"
        return formatter
    }()

    // MARK: Red (los cierres de Network llegan desde su propia cola)

    private static func start(_ connection: NWConnection) async throws {
        let gate = ResumeGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { @Sendable state in
                switch state {
                case .ready:
                    gate.once { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    gate.once { continuation.resume(throwing: error) }
                case .cancelled:
                    gate.once { continuation.resume(throwing: IMAPError.closed) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { @Sendable error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private static func receive(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { @Sendable data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: IMAPError.closed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

/// Para reanudar una continuación una sola vez aunque lleguen varios estados.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func once(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

// MARK: - Lectura de correos

/// Cabeceras (con palabras codificadas =?UTF-8?B?…?=) y texto legible de un correo.
enum MailText {
    static func headers(_ data: Data) -> [String: String] {
        let raw = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        // Las cabeceras largas siguen en líneas que empiezan por espacio.
        let unfolded = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: " ")
            .replacingOccurrences(of: "\n\t", with: " ")
        var result: [String: String] = [:]
        for line in unfolded.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = decodeWords(value)
        }
        return result
    }

    /// «Lucía Pérez <lucia@…>» → «Lucía Pérez».
    static func senderName(_ from: String) -> String {
        if let open = from.firstIndex(of: "<") {
            let name = from[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return name }
            return from[from.index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        }
        return from.trimmingCharacters(in: .whitespaces)
    }

    static func date(_ text: String?) -> Date {
        guard let text else { return .now }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            let cleaned = text.components(separatedBy: " (").first ?? text
            if let date = formatter.date(from: cleaned) { return date }
        }
        return .now
    }

    /// Palabras codificadas de RFC 2047 (base64 «B» o quoted-printable «Q»).
    static func decodeWords(_ text: String) -> String {
        guard text.contains("=?"),
              let regex = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=(\\s+(?==\\?))?") else { return text }
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let charsetRange = Range(match.range(at: 1), in: text),
                  let kindRange = Range(match.range(at: 2), in: text),
                  let payloadRange = Range(match.range(at: 3), in: text) else { continue }
            let payload = String(text[payloadRange])
            let bytes: Data? = text[kindRange].uppercased() == "B"
                ? Data(base64Encoded: payload.padding(toLength: ((payload.count + 3) / 4) * 4, withPad: "=", startingAt: 0))
                : quotedPrintable(payload.replacingOccurrences(of: "_", with: " "))
            guard let bytes else { continue }
            result.replaceCharacters(in: match.range, with: string(bytes, charset: String(text[charsetRange])))
        }
        return result as String
    }

    /// Texto legible del comienzo del cuerpo: quita MIME, base64, quoted-printable y HTML.
    static func body(_ data: Data) -> String {
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        // Si parece base64 (líneas largas sin espacios), se decodifica.
        let compact = lines.filter { !$0.isEmpty }
        if compact.count > 1, compact.allSatisfy({ !$0.contains(" ") }), (compact.first?.count ?? 0) >= 60,
           let decoded = Data(base64Encoded: compact.joined(), options: .ignoreUnknownCharacters),
           let string = String(data: decoded, encoding: .utf8) {
            text = string
        } else if text.contains("=\n") || text.contains("=\r\n") || text.range(of: "=[0-9A-F]{2}", options: .regularExpression) != nil,
                  let decoded = quotedPrintable(text) {
            text = string(decoded, charset: "utf-8")
        }
        text = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !line.hasPrefix("--") && !line.lowercased().hasPrefix("content-")
            }
            .joined(separator: "\n")
        text = text.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quotedPrintable(_ text: String) -> Data? {
        let soft = text.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "")
        var bytes = Data()
        var index = soft.utf8.startIndex
        let utf8 = soft.utf8
        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == UInt8(ascii: "="),
               let first = utf8.index(index, offsetBy: 1, limitedBy: utf8.endIndex), first < utf8.endIndex,
               let second = utf8.index(index, offsetBy: 2, limitedBy: utf8.endIndex), second < utf8.endIndex,
               let value = UInt8(String(decoding: [utf8[first], utf8[second]], as: UTF8.self), radix: 16) {
                bytes.append(value)
                index = utf8.index(after: second)
            } else {
                bytes.append(byte)
                index = utf8.index(after: index)
            }
        }
        return bytes
    }

    private static func string(_ data: Data, charset: String) -> String {
        let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        if encoding != kCFStringEncodingInvalidId,
           let string = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) {
            return string
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
