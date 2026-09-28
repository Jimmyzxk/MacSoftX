import Foundation
@testable import upmac

public final class MockBrewProvider: UpdateProvider, @unchecked Sendable {
    public let id: String = "brew"
    public let displayName: String = "Homebrew"

    public init() {}

    public func isAvailable() async -> Bool {
        return true
    }

    public func fetchOutdated() async throws -> [UpdateItem] {
        return [
            UpdateItem(
                providerId: id,
                name: "git",
                currentVersion: "2.43.0",
                latestVersion: "2.44.0",
                kind: .formula,
                needsSudo: false,
                requiresLogin: false
            ),
            UpdateItem(
                providerId: id,
                name: "visual-studio-code",
                currentVersion: "1.86.0",
                latestVersion: "1.87.0",
                kind: .cask,
                needsSudo: false,
                requiresLogin: false
            ),
            UpdateItem(
                providerId: id,
                name: "node",
                currentVersion: "20.11.0",
                latestVersion: "21.6.2",
                kind: .formula,
                needsSudo: false,
                requiresLogin: false
            ),
            UpdateItem(
                providerId: id,
                name: "wireshark-chmodbpf",
                currentVersion: "4.2.0",
                latestVersion: "4.2.2",
                kind: .cli,
                needsSudo: true,
                requiresLogin: false
            )
        ]
    }

    public func update(_ item: UpdateItem) async throws -> UpdateResult {
        try? await Task.sleep(nanoseconds: 500_000_000)
        return UpdateResult(
            ok: true,
            newVersion: item.latestVersion,
            message: "Updated \(item.name) successfully"
        )
    }
}
