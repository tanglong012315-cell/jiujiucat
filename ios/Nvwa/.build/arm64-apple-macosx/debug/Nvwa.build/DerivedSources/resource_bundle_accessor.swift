import Foundation

extension Foundation.Bundle {
    static nonisolated let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("Nvwa_Nvwa.bundle").path
        let buildPath = "/Users/user/Documents/Codex/2026-08-21/x20-365-12-ui/outputs/jiujiucat/ios/Nvwa/.build/arm64-apple-macosx/debug/Nvwa_Nvwa.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}