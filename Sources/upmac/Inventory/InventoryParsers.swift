import Foundation

public enum BrewListParser {
    public struct StringOrArray: Decodable {
        public let values: [String]
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                self.values = [single]
            } else if let array = try? container.decode([String].self) {
                self.values = array
            } else {
                self.values = []
            }
        }
    }

    public struct FormulaEntry: Decodable {
        public let name: String
        public let installed_versions: [String]?
        public let version: String?
    }

    public struct CaskEntry: Decodable {
        public let token: String
        public let name: StringOrArray?
        public let version: String?
        public let installed: String?
    }

    public struct ParseResult {
        public let formulae: [InventoryItem]
        public let casks: [InventoryItem]
        public var all: [InventoryItem] {
            formulae + casks
        }

        public init(formulae: [InventoryItem], casks: [InventoryItem]) {
            self.formulae = formulae
            self.casks = casks
        }
    }

    public static func parseDetailed(_ jsonString: String) throws -> ParseResult {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderError.parsingFailed("Empty JSON input")
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw ProviderError.parsingFailed("Invalid UTF-8 data")
        }

        let rawRoot: Any
        do {
            rawRoot = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ProviderError.parsingFailed("Failed to parse brew list JSON: \(error.localizedDescription)")
        }

        guard let root = rawRoot as? [String: Any] else {
            throw ProviderError.parsingFailed("Failed to parse brew list JSON: root is not a dictionary")
        }

        var formulae: [InventoryItem] = []
        if let rawFormulae = root["formulae"] as? [Any] {
            for item in rawFormulae {
                guard let f = item as? [String: Any] else { continue }
                guard let name = (f["name"] as? String) ?? (f["full_name"] as? String), !name.isEmpty else {
                    continue
                }

                // 宽容提取版本号：
                // 1. 新版 Homebrew --json --versions 结构: versions: ["2.44.0"] 取首元素
                // 2. linked_version / optlinked_version
                // 3. 旧版 Homebrew 结构容错: installed[0].version, installed_versions[0], versions.stable, version
                var version = "?"
                if let versionsArr = f["versions"] as? [String], let first = versionsArr.first, !first.isEmpty {
                    version = first
                } else if let versionsAnyArr = f["versions"] as? [Any], let first = versionsAnyArr.first {
                    let s = String(describing: first).trimmingCharacters(in: .whitespaces)
                    if !s.isEmpty { version = s }
                } else if let linked = f["linked_version"] as? String, !linked.isEmpty {
                    version = linked
                } else if let optlinked = f["optlinked_version"] as? String, !optlinked.isEmpty {
                    version = optlinked
                } else if let installedArr = f["installed"] as? [[String: Any]], let first = installedArr.first,
                          let ver = first["version"] as? String, !ver.isEmpty {
                    version = ver
                } else if let installedVersions = f["installed_versions"] as? [String], let first = installedVersions.first, !first.isEmpty {
                    version = first
                } else if let linkedKeg = f["linked_keg"] as? String, !linkedKeg.isEmpty {
                    version = linkedKeg
                } else if let versionsDict = f["versions"] as? [String: Any], let stable = versionsDict["stable"] as? String, !stable.isEmpty {
                    version = stable
                } else if let verStr = f["version"] as? String, !verStr.isEmpty {
                    version = verStr
                } else if let installedStr = f["installed"] as? String, !installedStr.isEmpty {
                    version = installedStr
                }

                formulae.append(InventoryItem(
                    id: "brew:\(name)",
                    name: name,
                    version: version,
                    kind: .cli,
                    sourceId: "brew",
                    sourceDisplayName: "Homebrew Formula",
                    status: .managed
                ))
            }
        }

        var casks: [InventoryItem] = []
        if let rawCasks = root["casks"] as? [Any] {
            for item in rawCasks {
                guard let c = item as? [String: Any] else { continue }
                // 新版 cask 结构只有 token 字段（无 name 字段）
                guard let token = (c["token"] as? String) ?? (c["name"] as? String), !token.isEmpty else {
                    continue
                }

                // 显示名称：优先 name 字段，若无则回退使用 token
                var displayName = token
                if let nameStr = c["name"] as? String, !nameStr.isEmpty {
                    displayName = nameStr
                } else if let nameArr = c["name"] as? [String], let first = nameArr.first, !first.isEmpty {
                    displayName = first
                } else if let nameAnyArr = c["name"] as? [Any], let first = nameAnyArr.first as? String, !first.isEmpty {
                    displayName = first
                }

                // 版本号提取：
                // 1. 新版 Homebrew --json --versions 结构: versions: ["4.27.1"] 取首元素
                // 2. 旧版结构容错: installed (String / Array / Object), version
                var version = "?"
                if let versionsArr = c["versions"] as? [String], let first = versionsArr.first, !first.isEmpty {
                    version = first
                } else if let versionsAnyArr = c["versions"] as? [Any], let first = versionsAnyArr.first {
                    let s = String(describing: first).trimmingCharacters(in: .whitespaces)
                    if !s.isEmpty { version = s }
                } else if let instStr = c["installed"] as? String, !instStr.isEmpty {
                    version = instStr
                } else if let instArr = c["installed"] as? [String], let first = instArr.first, !first.isEmpty {
                    version = first
                } else if let instAnyArr = c["installed"] as? [Any], let first = instAnyArr.first as? String, !first.isEmpty {
                    version = first
                } else if let instObjArr = c["installed"] as? [[String: Any]], let first = instObjArr.first,
                          let ver = first["version"] as? String, !ver.isEmpty {
                    version = ver
                } else if let verStr = c["version"] as? String, !verStr.isEmpty {
                    version = verStr
                } else if let verDict = c["versions"] as? [String: Any], let stable = verDict["stable"] as? String, !stable.isEmpty {
                    version = stable
                }

                casks.append(InventoryItem(
                    id: "brew-cask:\(token)",
                    name: displayName,
                    version: version,
                    kind: .app,
                    sourceId: "brew-cask",
                    sourceDisplayName: "Homebrew Cask",
                    status: .managed
                ))
            }
        }

        return ParseResult(formulae: formulae, casks: casks)
    }

    public static func parse(_ jsonString: String) throws -> [InventoryItem] {
        try parseDetailed(jsonString).all
    }
}

public enum MasListParser {
    private static let standardPattern = #"^(\d+)\s+(.+?)\s+\((.+?)\)\s*$"#
    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: standardPattern, options: [])
    }()

    public struct MasEntry: Equatable {
        public let id: String
        public let name: String
        public let version: String
    }

    public static func parseEntries(_ text: String) -> [MasEntry] {
        let lines = text.components(separatedBy: .newlines)
        var entries: [MasEntry] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            guard let reg = regex, let match = reg.firstMatch(in: line, options: [], range: fullRange),
                  match.numberOfRanges >= 4 else {
                continue
            }

            let id = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let name = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let version = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)

            entries.append(MasEntry(id: id, name: name, version: version))
        }

        return entries
    }

    public static func parse(_ text: String) -> [InventoryItem] {
        let entries = parseEntries(text)
        return entries.map { entry in
            InventoryItem(
                id: "mas:\(entry.id)",
                name: entry.name,
                version: entry.version,
                kind: .app,
                sourceId: "mas",
                sourceDisplayName: "Mac App Store",
                status: .managed,
                bundleId: nil,
                path: nil
            )
        }
    }
}

public enum NpmListParser {
    public static func parse(_ jsonString: String) throws -> [InventoryItem] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let data = trimmed.data(using: .utf8) else {
            throw ProviderError.parsingFailed("Invalid UTF-8 in npm list")
        }

        let rawRoot: Any
        do {
            rawRoot = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ProviderError.parsingFailed("Failed to parse npm ls JSON: \(error.localizedDescription)")
        }

        guard let root = rawRoot as? [String: Any],
              let deps = root["dependencies"] as? [String: Any] else {
            return []
        }

        return deps.keys.sorted().map { name in
            let depDict = deps[name] as? [String: Any]
            let version = depDict?["version"] as? String ?? "?"
            return InventoryItem(
                id: "npm:\(name)",
                name: name,
                version: version,
                kind: .cli,
                sourceId: "npm",
                sourceDisplayName: "npm",
                status: .managed
            )
        }
    }
}

public enum PipxListParser {
    public static func parse(_ jsonString: String) throws -> [InventoryItem] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let data = trimmed.data(using: .utf8) else {
            throw ProviderError.parsingFailed("Invalid UTF-8 in pipx list")
        }

        let rawRoot: Any
        do {
            rawRoot = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ProviderError.parsingFailed("Failed to parse pipx list JSON: \(error.localizedDescription)")
        }

        guard let root = rawRoot as? [String: Any],
              let venvs = root["venvs"] as? [String: Any] else {
            return []
        }

        return venvs.keys.sorted().map { name in
            let venvDict = venvs[name] as? [String: Any]
            let metaDict = venvDict?["metadata"] as? [String: Any]
            let mainPkgDict = metaDict?["main_package"] as? [String: Any]
            let version = mainPkgDict?["package_version"] as? String ?? "?"
            return InventoryItem(
                id: "pipx:\(name)",
                name: name,
                version: version,
                kind: .cli,
                sourceId: "pipx",
                sourceDisplayName: "pipx",
                status: .managed
            )
        }
    }
}

public enum UvToolListParser {
    public static func parse(_ text: String) -> [InventoryItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [InventoryItem] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("-") else { continue }

            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let name = parts.first else { continue }

            var version = "?"
            if parts.count >= 2 {
                let verPart = parts[1]
                version = verPart.hasPrefix("v") ? String(verPart.dropFirst()) : verPart
            }

            items.append(InventoryItem(
                id: "uv:\(name)",
                name: name,
                version: version,
                kind: .cli,
                sourceId: "uv",
                sourceDisplayName: "uv",
                status: .managed
            ))
        }

        return items
    }
}

public enum GemListParser {
    private static let pattern = #"^([a-zA-Z0-9_\-]+)\s*\(([^)]+)\)"#
    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [])
    }()

    public static func parse(_ text: String) -> [InventoryItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [InventoryItem] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            guard let reg = regex, let match = reg.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges >= 3 else {
                continue
            }

            let name = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let versionsRaw = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            // 取逗号前第一个版本号
            let firstVer = versionsRaw.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).first ?? "?"

            items.append(InventoryItem(
                id: "gem:\(name)",
                name: name,
                version: firstVer,
                kind: .cli,
                sourceId: "gem",
                sourceDisplayName: "RubyGems",
                status: .managed
            ))
        }

        return items
    }
}

public enum CargoListParser {
    /// 解析 cargo install-update -l 的表格输出
    public static func parse(_ text: String) -> [InventoryItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [InventoryItem] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // 忽略表头
            if line.contains("Package") && (line.contains("Installed") || line.contains("Latest")) {
                continue
            }

            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            var name = parts[0]
            if name.hasSuffix(":") {
                name = String(name.dropLast())
            }

            var ver = parts[1]
            if ver.hasPrefix("v") {
                ver = String(ver.dropFirst())
            }

            items.append(InventoryItem(
                id: "cargo:\(name)",
                name: name,
                version: ver,
                kind: .cli,
                sourceId: "cargo",
                sourceDisplayName: "Cargo",
                status: .managed
            ))
        }

        return items
    }

    /// 解析 cargo install --list 的标准输出
    public static func parseInstallList(_ text: String) -> [InventoryItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [InventoryItem] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // 格式：`cargo-tree v0.29.0:`
            if line.hasSuffix(":") {
                let stripped = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                let parts = stripped.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard let name = parts.first else { continue }

                var ver = "?"
                if parts.count >= 2 {
                    ver = parts[1]
                    if ver.hasPrefix("v") {
                        ver = String(ver.dropFirst())
                    }
                }

                items.append(InventoryItem(
                    id: "cargo:\(name)",
                    name: name,
                    version: ver,
                    kind: .cli,
                    sourceId: "cargo",
                    sourceDisplayName: "Cargo",
                    status: .managed
                ))
            }
        }

        return items
    }
}
