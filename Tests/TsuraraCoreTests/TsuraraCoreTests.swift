import Testing
@testable import TsuraraCore

@Test
func versionIsInitialRelease() {
    #expect(TsuraraCore.version == "0.1.0")
}
