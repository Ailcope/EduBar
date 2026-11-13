import Testing
@testable import EduBarCore

@Suite struct FeedLimitTests {
    @Test func plafondDe5Mo() {
        #expect(FeedLimit.maxBytes == 5_000_000)
    }

    @Test func tailleAnnonceeTropGrande() {
        #expect(FeedLimit.declaredTooLarge(expected: 12_500_000))
        #expect(!FeedLimit.declaredTooLarge(expected: 300_000))
        #expect(!FeedLimit.declaredTooLarge(expected: -1)) // inconnue : on compte à la réception
    }

    @Test func cumulTropGrand() {
        #expect(FeedLimit.exceeded(received: 5_000_001))
        #expect(!FeedLimit.exceeded(received: 5_000_000))
    }
}
