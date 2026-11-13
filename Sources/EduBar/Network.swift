import Foundation

/// Session réseau commune : aucun cache (ni mémoire ni disque), pour ne rien laisser dans
/// ~/Library/Caches (URL Edusign avec son jeton, coordonnées météo).
enum Network {
    static let session: URLSession = {
        purgeLegacyCache()
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Supprime le cache disque laissé par `URLSession.shared` dans ~/Library/Caches/<bundle id>.
    /// Ne touche qu'aux fichiers de ce cache (Cache.db*, fsCachedData).
    static func purgeLegacyCache() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID, isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasPrefix("Cache.db") || name == "fsCachedData" {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
