import Foundation

public struct ScanReport: Codable, Sendable {
    public struct ProviderReport: Codable, Sendable {
        public let providerId: String
        public let displayName: String
        public let isAvailable: Bool
        public let count: Int
        public let items: [UpdateItem]
        public let error: String?

        public init(
            providerId: String,
            displayName: String,
            isAvailable: Bool,
            count: Int,
            items: [UpdateItem],
            error: String? = nil
        ) {
            self.providerId = providerId
            self.displayName = displayName
            self.isAvailable = isAvailable
            self.count = count
            self.items = items
            self.error = error
        }
    }

    public let totalCount: Int
    public let providers: [ProviderReport]
    public let timestamp: String

    public init(
        totalCount: Int,
        providers: [ProviderReport],
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.totalCount = totalCount
        self.providers = providers
        self.timestamp = timestamp
    }
}

public enum ScanMode {
    public static func execute(
        providers: [any UpdateProvider] = [BrewProvider(), MasProvider(), AppUpdateProvider(), NpmProvider(), GemProvider(), UvProvider()],
        includeCask: Bool = true
    ) async -> ScanReport {
        var reports: [ScanReport.ProviderReport] = []

        await withTaskGroup(of: ScanReport.ProviderReport.self) { group in
            for provider in providers {
                group.addTask {
                    guard await provider.isAvailable() else {
                        return ScanReport.ProviderReport(
                            providerId: provider.id,
                            displayName: provider.displayName,
                            isAvailable: false,
                            count: 0,
                            items: [],
                            error: nil
                        )
                    }

                    do {
                        let items: [UpdateItem]
                        if !includeCask, let appProv = provider as? AppUpdateProvider {
                            items = try await appProv.fetchOutdatedWithoutCask()
                        } else {
                            items = try await provider.fetchOutdated()
                        }
                        return ScanReport.ProviderReport(
                            providerId: provider.id,
                            displayName: provider.displayName,
                            isAvailable: true,
                            count: items.count,
                            items: items,
                            error: nil
                        )
                    } catch {
                        return ScanReport.ProviderReport(
                            providerId: provider.id,
                            displayName: provider.displayName,
                            isAvailable: true,
                            count: 0,
                            items: [],
                            error: error.localizedDescription
                        )
                    }
                }
            }

            for await report in group {
                reports.append(report)
            }
        }

        reports.sort { $0.providerId < $1.providerId }
        let total = reports.reduce(0) { $0 + $1.count }

        return ScanReport(totalCount: total, providers: reports)
    }

    public static func run(
        providers: [any UpdateProvider] = [BrewProvider(), MasProvider(), AppUpdateProvider(), NpmProvider(), GemProvider(), UvProvider()],
        includeCask: Bool = true
    ) async {
        let report = await execute(providers: providers, includeCask: includeCask)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        } catch {
            print("{\"error\": \"Failed to encode scan report: \(error.localizedDescription)\"}")
        }
    }
}
