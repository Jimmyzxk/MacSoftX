import Foundation

public enum ToolPaths {
    public static func resolveCandidate(_ candidates: [String]) -> String? {
        for path in candidates {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }
        return nil
    }

    public static func brew() -> String? {
        BrewPaths.brewPath()
    }

    public static func mas() -> String? {
        BrewPaths.masPath()
    }

    public static func npm() -> String? {
        resolveCandidate([
            "~/.local/bin/npm",
            "/opt/homebrew/bin/npm",
            "/usr/local/bin/npm",
            "/usr/bin/npm",
            "~/.nvm/current/bin/npm"
        ])
    }

    public static func pipx() -> String? {
        resolveCandidate([
            "/opt/homebrew/bin/pipx",
            "/usr/local/bin/pipx",
            "~/.local/bin/pipx"
        ])
    }

    public static func uv() -> String? {
        resolveCandidate([
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            "~/.cargo/bin/uv",
            "~/.local/bin/uv"
        ])
    }

    public static func gem() -> String? {
        resolveCandidate([
            "/usr/bin/gem",
            "/opt/homebrew/bin/gem",
            "/usr/local/bin/gem",
            "~/.local/bin/gem"
        ])
    }

    public static func cargo() -> String? {
        resolveCandidate([
            "~/.cargo/bin/cargo",
            "/opt/homebrew/bin/cargo",
            "/usr/local/bin/cargo"
        ])
    }
}
