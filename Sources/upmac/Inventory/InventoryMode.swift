import Foundation

public enum InventoryMode {
    public static func execute() async -> InventoryReport {
        await InventoryService.performScan()
    }

    public static func run() async {
        let report = await execute()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        } catch {
            print("{\"error\": \"Failed to encode inventory report: \(error.localizedDescription)\"}")
        }
    }
}
