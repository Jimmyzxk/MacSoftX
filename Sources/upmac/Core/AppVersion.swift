import Foundation

public enum AppVersion {
    public static var short: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    public static var display: String {
        "v" + short
    }
}
