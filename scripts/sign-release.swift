// Signature Ed25519 des archives de mise à jour d'EduBar (CryptoKit, aucune dépendance).
// Outil de publication, hors de l'app : ce fichier n'entre pas dans le binaire EduBar.
//
// Usage (depuis la racine du dépôt) :
//   swift scripts/sign-release.swift keygen       crée la clé privée (une seule fois), affiche la clé publique
//   swift scripts/sign-release.swift pubkey       réaffiche la clé publique
//   swift scripts/sign-release.swift sign <zip>   écrit <zip>.sig (base64 de 64 octets) et le vérifie
//   swift scripts/sign-release.swift sign --add <zip>   ajoute une signature au .sig (rotation de clé)
//
// Clé privée : ~/.config/edubar/release-signing.key (dossier 0700, fichier 0600),
// ou le chemin donné par la variable d'environnement EDUBAR_SIGNING_KEY.
// Format : base64 des 32 octets bruts de la clé, suivi d'un saut de ligne.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sign-release : \(message)\n".utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

let keyPath: String = {
    if let custom = ProcessInfo.processInfo.environment["EDUBAR_SIGNING_KEY"], !custom.isEmpty { return custom }
    return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/edubar/release-signing.key").path
}()

func publicKeyBase64(_ key: Curve25519.Signing.PrivateKey) -> String {
    key.publicKey.rawRepresentation.base64EncodedString()
}

/// Contenu d'un .sig → une signature de 64 octets par ligne (même règle que Update.signatures(fromFile:)
/// dans l'app : 512 octets au plus, une ligne mal formée invalide tout).
func decodeSignatures(_ data: Data) -> [Data] {
    guard data.count <= 512, let text = String(data: data, encoding: .utf8) else { return [] }
    var result: [Data] = []
    for line in text.split(whereSeparator: \.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        guard let raw = Data(base64Encoded: trimmed), raw.count == 64 else { return [] }
        result.append(raw)
    }
    return result
}

func keygen() {
    let fm = FileManager.default
    let dir = URL(fileURLWithPath: keyPath).deletingLastPathComponent()
    if !fm.fileExists(atPath: dir.path) {
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            fail("impossible de créer \(dir.path) : \(error.localizedDescription)")
        }
    }
    // O_EXCL : jamais d'écrasement d'une clé existante (ni d'écriture à travers un lien) ; 0600 dès la création.
    let fd = open(keyPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard fd >= 0 else {
        if errno == EEXIST { fail("une clé existe déjà dans \(keyPath) : rien n'est écrasé.") }
        fail("impossible de créer \(keyPath) : \(String(cString: strerror(errno))).")
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    let key = Curve25519.Signing.PrivateKey()
    do {
        guard fchmod(fd, 0o600) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        try handle.write(contentsOf: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8))
        try handle.synchronize()
        try handle.close()
    } catch {
        try? fm.removeItem(atPath: keyPath)
        fail("écriture de la clé impossible : \(error.localizedDescription)")
    }
    // Seule la clé publique sort sur stdout ; la clé privée n'est jamais affichée.
    print(publicKeyBase64(key))
    note("""
    Clé privée créée : \(keyPath) (0600).
    1. Sauvegarde-la hors du Mac (gestionnaire de mots de passe, support chiffré).
    2. Colle la clé publique ci-dessus dans Sources/EduBarCore/Update.swift (releasePublicKey).
    """)
}

func readKey() -> Curve25519.Signing.PrivateKey {
    var info = stat()
    guard stat(keyPath, &info) == 0 else { fail("aucune clé dans \(keyPath) (la créer avec keygen).") }
    guard info.st_mode & S_IFMT == S_IFREG else { fail("\(keyPath) n'est pas un fichier.") }
    guard info.st_mode & 0o077 == 0 else { fail("\(keyPath) est accessible à d'autres comptes : chmod 600 \(keyPath)") }
    guard let text = try? String(contentsOfFile: keyPath, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 32,
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("clé illisible dans \(keyPath).") }
    return key
}

/// `add` : ajoute une ligne au .sig existant au lieu de le remplacer (rotation : deux clés signent).
func sign(_ zipPath: String, add: Bool = false) {
    let key = readKey()
    let fm = FileManager.default
    guard let archive = fm.contents(atPath: zipPath), !archive.isEmpty else { fail("archive illisible ou vide : \(zipPath)") }
    let sigPath = zipPath + ".sig"
    do {
        var lines: [String] = []
        if add {
            guard let existing = fm.contents(atPath: sigPath), !decodeSignatures(existing).isEmpty else {
                fail("pas de \(sigPath) valide à compléter (signer d'abord sans --add).")
            }
            lines = decodeSignatures(existing).map { $0.base64EncodedString() }
        }
        lines.append(try key.signature(for: archive).base64EncodedString())
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: sigPath), options: .atomic)
    } catch {
        fail("signature impossible : \(error.localizedDescription)")
    }
    // Contrôle : relit l'archive et le .sig sur disque et vérifie avec la clé publique.
    guard let written = fm.contents(atPath: sigPath), let reread = fm.contents(atPath: zipPath),
          decodeSignatures(written).contains(where: { key.publicKey.isValidSignature($0, for: reread) })
    else {
        try? fm.removeItem(atPath: sigPath)
        fail("la signature écrite ne se vérifie pas, \(sigPath) supprimé.")
    }
    print(sigPath)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case ("keygen", 1): keygen()
case ("pubkey", 1): print(publicKeyBase64(readKey()))
case ("sign", 2): sign(arguments[1])
case ("sign", 3) where arguments[1] == "--add": sign(arguments[2], add: true)
default:
    note("""
    Usage : swift scripts/sign-release.swift keygen | pubkey | sign [--add] <zip>
    Clé : \(keyPath) (variable EDUBAR_SIGNING_KEY pour un autre chemin)
    """)
    exit(2)
}
