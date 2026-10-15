import EduBarCore
import Foundation

/// `EduBar --myges-dump` : imprime le JSON brut de `years`, de l'agenda et des notes (diagnostic).
/// Ne montre jamais le jeton ni les identifiants.
enum MyGESDump {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--myges-dump") else { return }
        guard let creds = MyGESCredentialsFile.read() else {
            fail("Aucun identifiant myGES : \(MyGESCredentialsFile.standard.url.path) est absent ou illisible.")
        }
        Task {
            do {
                let client = MyGESClient { creds }
                _ = try await client.authenticate(creds)
                try await print(client, "years", KordisAPI.yearsURL)
                let range = KordisAPI.agendaRange(now: Date(), calendar: .current)
                try await print(client, "agenda", KordisAPI.agendaURL(from: range.from, to: range.to))
                let year = try await client.years().max() ?? KordisAPI.currentSchoolYear(now: Date(), calendar: .current)
                try await print(client, "grades", KordisAPI.gradesURL(year: year))
                exit(0)
            } catch {
                fail(error.localizedDescription)
            }
        }
        dispatchMain()
    }

    private static func print(_ client: MyGESClient, _ name: String, _ url: URL) async throws {
        let data = try await client.rawJSON(url)
        Swift.print("=== \(name): \(url.absoluteString) ===")
        Swift.print(String(decoding: data, as: UTF8.self))
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("EduBar --myges-dump : " + message + "\n").utf8))
        exit(1)
    }
}
