import Testing

// swift-testing のテストを実行ターゲットとして走らせるためのエントリポイント。
// SPM が Xcode 環境で行う synthesize と同等の処理を明示的に書いている。
@main struct TestRunner {
    static func main() async {
        await __swiftPMEntryPoint() as Never
    }
}
