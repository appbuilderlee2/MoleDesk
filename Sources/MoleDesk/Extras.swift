import Foundation

struct TrashRecord: Codable, Identifiable {
    var id: UUID
    var original: String
    var trashed: String
    var category: String
    var date: Date
    var restored: Bool
}

enum HistoryStore {
    private static let lock = NSLock()
    private static var location: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MoleDesk", isDirectory: true)
            .appendingPathComponent("trash-history.json")
    }
    private static func read() -> [TrashRecord] {
        guard let data = try? Data(contentsOf: location),
              let records = try? JSONDecoder().decode([TrashRecord].self, from: data) else { return [] }
        return records
    }
    private static func save(_ records: [TrashRecord]) {
        try? FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: location, options: .atomic) }
    }
    static func load() -> [TrashRecord] {
        lock.lock(); defer { lock.unlock() }
        return read().sorted { $0.date > $1.date }
    }
    static func record(original: URL, trash: URL, category: String) {
        lock.lock(); defer { lock.unlock() }
        var items = read()
        items.insert(TrashRecord(id: UUID(), original: original.path, trashed: trash.path,
                                 category: category, date: Date(), restored: false), at: 0)
        save(Array(items.prefix(500)))
    }
    static func restore(_ item: TrashRecord) -> String {
        lock.lock(); defer { lock.unlock() }
        var items = read()
        guard let index = items.firstIndex(where: { $0.id == item.id }), !items[index].restored else { return "紀錄已不存在或已還原" }
        let fm = FileManager.default
        let source = URL(fileURLWithPath: item.trashed)
        let destination = URL(fileURLWithPath: item.original)
        guard fm.fileExists(atPath: source.path) else { return "垃圾桶內已找不到檔案，可能已清空" }
        guard !fm.fileExists(atPath: destination.path) else { return "原本位置已有同名檔案，停止還原" }
        guard fm.fileExists(atPath: destination.deletingLastPathComponent().path) else { return "原本資料夾不存在，停止還原" }
        do {
            try fm.moveItem(at: source, to: destination)
            items[index].restored = true
            save(items)
            return "已還原：" + destination.lastPathComponent
        } catch { return "還原失敗：" + error.localizedDescription }
    }
}

enum ResidualScanner {
    private static let folders = [
        "Library/Application Support", "Library/Preferences", "Library/Caches", "Library/Logs",
        "Library/Saved Application State", "Library/Containers", "Library/Group Containers",
        "Library/HTTPStorages", "Library/WebKit"
    ]
    static func isAllowed(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false else { return false }
        return folders.contains { prefix in
            let parent = home + "/" + prefix
            return p.hasPrefix(parent + "/") && URL(fileURLWithPath: p).deletingLastPathComponent().path == parent
        }
    }
    static func candidates(for app: URL) -> [URL] {
        guard app.pathExtension.lowercased() == "app" else { return [] }
        let name = app.deletingPathExtension().lastPathComponent.lowercased()
        guard name.count >= 4 else { return [] }
        let identifier = (Bundle(url: app)?.bundleIdentifier ?? "").lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found: [URL] = []
        for folder in folders {
            let parent = home.appendingPathComponent(folder, isDirectory: true)
            let children = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
            for child in children {
                let filename = child.lastPathComponent.lowercased()
                let stem = (filename as NSString).deletingPathExtension
                let matchingID = identifier.count >= 6 && (filename == identifier || stem == identifier || filename.hasPrefix(identifier + "."))
                let matchingName = stem == name || filename == name
                if (matchingID || matchingName) && isAllowed(child) { found.append(child) }
            }
        }
        return Array(Set(found.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }
    }
}
