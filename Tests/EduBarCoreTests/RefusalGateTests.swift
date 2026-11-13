import Foundation
import Testing
@testable import EduBarCore

@Suite struct RefusalGateTests {
    let creds = MyGESCredentials(login: "a.b", password: "vieux")

    /// Simule un refresh automatique : n'appelle le « réseau » que si la porte l'autorise.
    func autoRefresh(_ gate: inout RefusalGate, calls: inout Int, status: Int) {
        guard gate.allows(creds) else { return }
        calls += 1
        if status == 401 || status == 403 { gate.recordRefusal(of: creds) }
    }

    @Test func refusalStopsAutomaticAttempts() {
        var gate = RefusalGate()
        var calls = 0
        autoRefresh(&gate, calls: &calls, status: 401)
        autoRefresh(&gate, calls: &calls, status: 401)
        autoRefresh(&gate, calls: &calls, status: 401)
        #expect(calls == 1)
    }

    @Test func temporaryErrorsDoNotBlock() {
        var gate = RefusalGate()
        var calls = 0
        for status in [429, 500, 503, 0] { autoRefresh(&gate, calls: &calls, status: status) }
        #expect(calls == 4)
    }

    @Test func newCredentialsUnblock() {
        var gate = RefusalGate()
        gate.recordRefusal(of: creds)
        #expect(!gate.allows(creds))
        #expect(gate.allows(MyGESCredentials(login: "a.b", password: "neuf")))
    }

    @Test func manualRetryUnblocks() {
        var gate = RefusalGate()
        gate.recordRefusal(of: creds)
        gate.reset()
        #expect(gate.allows(creds))
    }
}
