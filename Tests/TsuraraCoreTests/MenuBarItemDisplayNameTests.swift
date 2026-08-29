import Testing
import TsuraraCore

@Suite
struct MenuBarItemDisplayNameTests {
    @Test
    func resolvesBundleIdentifierThroughInjectedResolver() {
        let result = MenuBarItemDisplayName.resolve(
            title: "com.elgato.StreamDeck",
            ownerName: "Control Center",
            appNameForBundleID: { $0 == "com.elgato.StreamDeck" ? "Stream Deck" : nil }
        )

        #expect(result == "Stream Deck")
    }

    @Test
    func keepsBundleIdentifierWhenResolverCannotResolveIt() {
        let result = MenuBarItemDisplayName.resolve(
            title: "com.example.Unknown",
            ownerName: "Control Center",
            appNameForBundleID: { _ in nil }
        )

        #expect(result == "com.example.Unknown")
    }

    @Test(arguments: [
        nil,
        "",
        "Item-0",
        "991",
        "550e8400-e29b-41d4-a716-446655440000",
    ] as [String?])
    func fallsBackToOwnerNameForMissingOrGenericTitles(title: String?) {
        let result = MenuBarItemDisplayName.resolve(
            title: title,
            ownerName: "Control Center",
            appNameForBundleID: { _ in "Unexpected" }
        )

        #expect(result == "Control Center")
    }

    @Test
    func keepsHumanReadableTitle() {
        let result = MenuBarItemDisplayName.resolve(
            title: "WiFi",
            ownerName: "Control Center",
            appNameForBundleID: { _ in nil }
        )

        #expect(result == "WiFi")
    }
}
