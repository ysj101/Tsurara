import Testing
import TsuraraCore

@Test
func versionIsSemanticVersion() {
    // バージョンの正本は TsuraraCore.version（Scripts/make-app.sh がバンドルへ反映する）。
    #expect(TsuraraCore.version.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
}
