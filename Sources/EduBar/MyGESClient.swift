import EduBarCore
import Foundation

enum MyGESError: LocalizedError {
    case noCredentials
    case badCredentials
    case unexpectedResponse
    case unavailable(Int)
    case http(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials: "Aucun identifiant myGES enregistré."
        case .badCredentials: "Identifiant ou mot de passe refusé par myGES."
        case .unexpectedResponse: "Réponse inattendue de myGES."
        case let .unavailable(code): "myGES indisponible (\(code))."
        case let .http(code): "myGES a répondu \(code)."
        case let .network(text): "Connexion à myGES impossible : \(text)"
        }
    }
}

/// Refuse de suivre les redirections : le jeton est dans l'en-tête `Location` du 302.
private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Client de l'API Kordis (myGES). Le jeton reste en mémoire ; les identifiants sont demandés à chaque
/// connexion via `credentialsProvider` et ne sont jamais gardés ici.
actor MyGESClient {
    private let session: URLSession
    private let credentialsProvider: @Sendable () -> MyGESCredentials?
    private var token: (value: String, type: String, expires: Date)?

    init(credentialsProvider: @escaping @Sendable () -> MyGESCredentials?) {
        self.credentialsProvider = credentialsProvider
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }

    // MARK: - Authentification

    /// Demande un jeton avec ces identifiants (sans toucher au cache).
    func authenticate(_ creds: MyGESCredentials) async throws -> KordisToken {
        var request = URLRequest(url: KordisAPI.authorizeURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(KordisAPI.basicAuthorization(creds), forHTTPHeaderField: "Authorization")
        request.setValue(KordisAPI.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await send(request).response
        let code = response.statusCode
        if let location = response.value(forHTTPHeaderField: "Location"), (300..<400).contains(code) {
            guard let token = KordisToken.parse(location: location) else { throw MyGESError.unexpectedResponse }
            return token
        }
        if code == 429 || code >= 500 { throw MyGESError.unavailable(code) }
        if code == 401 || code == 403 { throw MyGESError.badCredentials }
        throw MyGESError.unexpectedResponse
    }

    private func validToken(forceRefresh: Bool = false) async throws -> (value: String, type: String) {
        if !forceRefresh, let token, token.expires > Date() { return (token.value, token.type) }
        guard let creds = credentialsProvider() else { throw MyGESError.noCredentials }
        let fresh = try await authenticate(creds)
        // Marge de 60 s ; repli à 1 h si le serveur n'annonce pas de durée.
        let ttl = max(0, (fresh.expiresIn ?? 3600) - 60)
        token = (fresh.accessToken, fresh.tokenType, Date().addingTimeInterval(ttl))
        return (fresh.accessToken, fresh.tokenType)
    }

    // MARK: - Routes

    /// Corps brut d'une route de l'API (diagnostic). Sur 401, se reconnecte une fois et rejoue.
    func rawJSON(_ url: URL) async throws -> Data {
        var forceRefresh = false
        for attempt in 0..<2 {
            let auth = try await validToken(forceRefresh: forceRefresh)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue(auth.type.lowercased() == "bearer" ? "Bearer \(auth.value)" : "\(auth.type) \(auth.value)", forHTTPHeaderField: "Authorization")
            request.setValue(KordisAPI.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await send(request)
            switch response.statusCode {
            case 200..<300: return data
            case 401 where attempt == 0:
                token = nil
                forceRefresh = true
            case 401: throw MyGESError.badCredentials
            case 429, 500...: throw MyGESError.unavailable(response.statusCode)
            default: throw MyGESError.http(response.statusCode)
            }
        }
        throw MyGESError.unexpectedResponse
    }

    func agenda(from: Date, to: Date) async throws -> [Course] {
        let data = try await rawJSON(KordisAPI.agendaURL(from: from, to: to))
        do { return GESAgenda.courses(from: try GESAgenda.events(from: data)) } catch { throw MyGESError.unexpectedResponse }
    }

    /// Années scolaires de l'étudiant ; repli sur l'année scolaire courante si la liste est vide.
    func years() async throws -> [Int] {
        let years = KordisAPI.years(from: try await rawJSON(KordisAPI.yearsURL))
        return years.isEmpty ? [KordisAPI.currentSchoolYear(now: Date(), calendar: .current)] : years
    }

    func grades(year: Int) async throws -> GradeBook {
        let data = try await rawJSON(KordisAPI.gradesURL(year: year))
        do { return try GESGrades.gradeBook(from: data) } catch { throw MyGESError.unexpectedResponse }
    }

    func gradesCurrentYear() async throws -> GradeBook {
        let year = try await years().max() ?? KordisAPI.currentSchoolYear(now: Date(), calendar: .current)
        return try await grades(year: year)
    }

    private func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw MyGESError.unexpectedResponse }
            return (data, http)
        } catch let error as MyGESError {
            throw error
        } catch {
            throw MyGESError.network((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
