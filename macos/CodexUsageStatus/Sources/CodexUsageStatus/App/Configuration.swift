import Foundation

enum AppConfig {
    static let defaultCodexPaths = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex"
    ]
    static let minimumRefreshInterval: TimeInterval = 60
    static let defaultRefreshInterval: TimeInterval = 120
    static let errorRetryInterval: TimeInterval = 300
    static let appServerTimeout: DispatchTimeInterval = .seconds(20)

    static func codexPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String {
        if let override = environment["CODEX_BIN"], !override.isEmpty {
            return override
        }

        return defaultCodexPaths.first(where: fileManager.isExecutableFile(atPath:))
            ?? defaultCodexPaths[0]
    }
}

func configuredRefreshInterval() -> TimeInterval {
    let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"]
    let requested = rawValue.flatMap(Double.init) ?? AppConfig.defaultRefreshInterval
    return max(AppConfig.minimumRefreshInterval, requested)
}
