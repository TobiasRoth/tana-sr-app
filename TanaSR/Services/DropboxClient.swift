import Foundation

enum DropboxError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Nicht mit Dropbox verbunden."
        case .invalidResponse: return "Unerwartete Antwort von Dropbox."
        case .httpError(let code, let body): return "Dropbox-Fehler \(code): \(body)"
        }
    }
}

/// Spricht die Dropbox-API direkt an (App-Folder-Scope: Pfade sind relativ zum
/// App-Ordner, z.B. "/cards.json"). Token-Refresh per PKCE-Refresh-Token, kein
/// Client-Secret noetig (verifiziert 27.08.2026, siehe Scripts/tana-sr/authorize_dropbox.py).
actor DropboxClient {
    static let refreshTokenKey = "dropbox_refresh_token"
    private static let appKey = "mnrl1klwytt1trq"

    private var cachedAccessToken: String?
    private var cachedAccessTokenExpiry: Date?

    var isAuthenticated: Bool {
        KeychainStore.load(forKey: Self.refreshTokenKey) != nil
    }

    func connect(refreshToken: String) {
        KeychainStore.save(refreshToken, forKey: Self.refreshTokenKey)
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil
    }

    func disconnect() {
        KeychainStore.delete(forKey: Self.refreshTokenKey)
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil
    }

    private func accessToken() async throws -> String {
        if let token = cachedAccessToken, let expiry = cachedAccessTokenExpiry, expiry > Date() {
            return token
        }
        guard let refreshToken = KeychainStore.load(forKey: Self.refreshTokenKey) else {
            throw DropboxError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: Self.appKey),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DropboxError.invalidResponse }
        guard http.statusCode == 200 else {
            throw DropboxError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedAccessToken = decoded.accessToken
        cachedAccessTokenExpiry = Date().addingTimeInterval(TimeInterval(decoded.expiresIn - 60))
        return decoded.accessToken
    }

    /// Laedt eine Datei aus dem App-Ordner. Wirft DropboxError.httpError(409, ...)
    /// bei "path/not_found" -- Aufrufer entscheidet, ob das ein leerer Startzustand ist.
    func download(path: String) async throws -> Data {
        let token = try await accessToken()
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(#"{"path": "\#(path)"}"#, forHTTPHeaderField: "Dropbox-API-Arg")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DropboxError.invalidResponse }
        guard http.statusCode == 200 else {
            throw DropboxError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func upload(path: String, data: Data) async throws {
        let token = try await accessToken()
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(#"{"path": "\#(path)", "mode": "overwrite"}"#, forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DropboxError.invalidResponse }
        guard http.statusCode == 200 else {
            throw DropboxError.httpError(http.statusCode, String(data: responseData, encoding: .utf8) ?? "")
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }
}
