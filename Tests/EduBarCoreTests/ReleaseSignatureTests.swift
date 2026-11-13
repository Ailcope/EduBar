import CryptoKit
import Foundation
import Testing
@testable import EduBarCore

/// Signature Ed25519 des archives de mise à jour. Les clés sont des clés de TEST, tirées en mémoire
/// à chaque test et jamais écrites sur disque.
@Suite struct ReleaseSignatureTests {
    let key = Curve25519.Signing.PrivateKey()
    let archive = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })

    var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    /// Contenu du fichier .sig tel que l'écrit scripts/sign-release.swift : base64 + saut de ligne.
    func sigFile(_ signature: Data) -> Data { Data((signature.base64EncodedString() + "\n").utf8) }

    func signed(_ data: Data, by k: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        sigFile(try (k ?? key).signature(for: data))
    }

    @Test func signatureValideAcceptee() throws {
        #expect(Update.verifySignature(try signed(archive), of: archive, publicKey: publicKey))
    }

    @Test func blancsDeDebutEtDeFinToleres() throws {
        let b64 = try key.signature(for: archive).base64EncodedString()
        for text in [b64, b64 + "\r\n", "  " + b64 + "\n\n"] {
            #expect(Update.verifySignature(Data(text.utf8), of: archive, publicKey: publicKey))
        }
    }

    @Test func archiveModifieeDUnOctetRefusee() throws {
        let sig = try signed(archive)
        for index in [0, archive.count / 2, archive.count - 1] {
            var altered = archive
            altered[index] ^= 0x01
            #expect(!Update.verifySignature(sig, of: altered, publicKey: publicKey))
        }
        #expect(!Update.verifySignature(sig, of: archive + Data([0]), publicKey: publicKey))
        #expect(!Update.verifySignature(sig, of: archive.dropLast(), publicKey: publicKey))
    }

    @Test func signatureDUneAutreCleRefusee() throws {
        let other = Curve25519.Signing.PrivateKey()
        #expect(!Update.verifySignature(try signed(archive, by: other), of: archive, publicKey: publicKey))
    }

    @Test func signatureAbsenteTronqueeOuMalFormeeRefusee() throws {
        let b64 = try key.signature(for: archive).base64EncodedString()
        let bad: [Data] = [
            Data(), // absente
            Data("\n".utf8),
            Data(b64.dropLast(4).utf8), // tronquée
            Data(try key.signature(for: archive).prefix(63).base64EncodedString().utf8), // 63 octets
            Data((b64 + "AAAA").utf8), // 67 octets
            Data("!!!!".utf8), // base64 invalide
            Data((String(b64.dropLast(2)) + "*=").utf8),
            Data(("-" + b64.dropFirst()).utf8), // caractère hors alphabet base64
            try key.signature(for: archive), // octets bruts au lieu du base64
            Data([0xFF, 0xFE, 0x00]), // pas de l'UTF-8
            Data((String(repeating: "A", count: 86) + "==").utf8), // 64 octets à zéro
        ]
        for file in bad {
            #expect(!Update.verifySignature(file, of: archive, publicKey: publicKey))
        }
        #expect(Update.signatures(fromFile: Data()).isEmpty)
        #expect(Update.signatures(fromFile: Data(b64.dropLast(4).utf8)).isEmpty)
        #expect(Update.signatures(fromFile: Data(b64.utf8)).map(\.count) == [64])
    }

    /// Rotation de clé : le .sig porte une signature par ligne (ancienne et nouvelle clé) ; une app
    /// qui n'épingle que l'une des deux accepte, quel que soit l'ordre.
    @Test func plusieursSignaturesUneSeuleSuffit() throws {
        let other = Curve25519.Signing.PrivateKey()
        let mine = try key.signature(for: archive).base64EncodedString()
        let theirs = try other.signature(for: archive).base64EncodedString()
        for text in ["\(mine)\n\(theirs)\n", "\(theirs)\n\(mine)\n", "\(theirs)\r\n\r\n\(mine)"] {
            #expect(Update.verifySignature(Data(text.utf8), of: archive, publicKey: publicKey))
        }
        // Aucune ligne de la bonne clé : refusé.
        #expect(!Update.verifySignature(Data("\(theirs)\n\(theirs)\n".utf8), of: archive, publicKey: publicKey))
        // Une ligne mal formée invalide tout le fichier, même à côté d'une bonne signature.
        #expect(!Update.verifySignature(Data("\(mine)\nn'importe quoi\n".utf8), of: archive, publicKey: publicKey))
    }

    @Test func fichierSigTropGrosRefuse() throws {
        // Signature valide noyée dans des blancs : au-delà du plafond, refusée sans être lue.
        let b64 = try key.signature(for: archive).base64EncodedString()
        let padded = b64 + String(repeating: "\n", count: Update.maxSignatureBytes)
        #expect(Update.signatures(fromFile: Data(padded.utf8)).isEmpty)
        #expect(!Update.verifySignature(Data(padded.utf8), of: archive, publicKey: publicKey))
        #expect(Update.maxSignatureBytes <= 1024)
    }

    @Test func clePubliqueMalFormeeRefusee() {
        let zeros = Data(count: 32).base64EncodedString()
        for bad in ["", "pas du base64", Data(count: 31).base64EncodedString(), Data(count: 33).base64EncodedString(), zeros] {
            #expect(Update.publicKey(base64: bad) == nil)
        }
        #expect(Update.publicKey(base64: publicKey) != nil)
        #expect(Update.publicKey(base64: " \(publicKey)\n") != nil)
    }

    @Test func clePubliqueMalFormeeNeValideRien() throws {
        let sig = try signed(archive)
        #expect(!Update.verifySignature(sig, of: archive, publicKey: ""))
        #expect(!Update.verifySignature(sig, of: archive, publicKey: Data(count: 32).base64EncodedString()))
    }

    /// Une clé épinglée nulle ou mal formée bloquerait toutes les mises à jour.
    @Test func cleEpingleeValide() {
        #expect(Update.publicKey(base64: Update.releasePublicKey) != nil)
    }

    @Test func cleEpingleeParDefautRefuseLaCleDeTest() throws {
        #expect(!Update.verifySignature(try signed(archive), of: archive))
    }
}

@Suite struct ReleaseSignatureAssetTests {
    func release(_ assets: String) throws -> Release {
        try Update.decode(Data(#"{"tag_name":"v1.2.0","html_url":"https://github.com/Ailcope/EduBar/releases/tag/v1.2.0","assets":[\#(assets)]}"#.utf8))
    }

    let zip = #"{"name":"EduBar-1.2.0.zip","browser_download_url":"https://github.com/r/EduBar-1.2.0.zip","digest":"sha256:\#(String(repeating: "ab", count: 32))"}"#

    func asset(_ name: String, _ url: String) -> String {
        #"{"name":"\#(name)","browser_download_url":"\#(url)"}"#
    }

    @Test func urlDeLaSignatureExtraite() throws {
        let r = try release(zip + "," + asset("EduBar-1.2.0.zip.sig", "https://github.com/r/EduBar-1.2.0.zip.sig"))
        #expect(r.zipSignature?.absoluteString == "https://github.com/r/EduBar-1.2.0.zip.sig")
        #expect(r.zip?.absoluteString == "https://github.com/r/EduBar-1.2.0.zip")
        #expect(Update.available(r, current: "1.1.0") == r)
    }

    @Test func releaseSansAssetSig() throws {
        let r = try release(zip + "," + asset("EduBar-1.2.0.dmg", "https://github.com/r/EduBar-1.2.0.dmg"))
        #expect(r.zipSignature == nil)
        // Plus récente mais non signée : ni installée ni proposée.
        #expect(Update.isNewer(r, than: "1.1.0"))
        #expect(Update.available(r, current: "1.1.0") == nil)
    }

    @Test func signatureDUnAutreFichierIgnoree() throws {
        let r = try release(zip + "," + asset("EduBar-1.2.0.dmg.sig", "https://github.com/r/EduBar-1.2.0.dmg.sig")
            + "," + asset("EduBar-1.1.0.zip.sig", "https://github.com/r/EduBar-1.1.0.zip.sig")
            + "," + asset("EduBar-1.2.0.sig", "https://github.com/r/EduBar-1.2.0.sig"))
        #expect(r.zipSignature == nil)
    }

    @Test func signatureHorsHTTPSIgnoree() throws {
        for url in ["http://github.com/r/EduBar-1.2.0.zip.sig", "file:///tmp/EduBar-1.2.0.zip.sig"] {
            let r = try release(zip + "," + asset("EduBar-1.2.0.zip.sig", url))
            #expect(r.zipSignature == nil)
        }
    }

    @Test func archiveHorsHTTPSIgnoree() throws {
        let plain = zip.replacingOccurrences(of: "https://", with: "http://")
        let r = try release(plain + "," + asset("EduBar-1.2.0.zip.sig", "https://github.com/r/EduBar-1.2.0.zip.sig"))
        #expect(r.zip == nil)
        #expect(r.zipSHA256 == nil)
        #expect(r.zipSignature == nil)
    }

    @Test func sha256DesOctets() {
        #expect(Update.sha256(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
