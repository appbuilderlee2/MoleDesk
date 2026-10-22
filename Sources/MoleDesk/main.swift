import SwiftUI
import AppKit
import Foundation

@main struct MoleDeskApp: App {
    var body: some Scene { WindowGroup("MoleDesk") { MainView() } }
}

struct Item: Identifiable {
    let url: URL
    let bytes: Int64
    var id: String { url.path }
}

enum Page: String, CaseIterable, Identifiable {
    case home = "總覽", clean = "安全清理", apps = "App 卸載", residual = "App 殘留", disk = "磁碟分析", history = "還原紀錄", mole = "Mole 預覽"
    var id: String { rawValue }
}

func formatBytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

func folderSize(_ url: URL) -> Int64 {
    let fm = FileManager.default
    guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey]), v.isSymbolicLink != true else { return 0 }
    if v.isDirectory != true { return Int64(v.fileSize ?? 0) }
    guard let it = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey], options: [.skipsPackageDescendants], errorHandler: { _,_ in true }) else { return 0 }
    var sum: Int64 = 0, count = 0
    for case let file as URL in it {
        count += 1
        if count > 15000 { break }
        if let p = try? file.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey]) {
            if p.isSymbolicLink == true { it.skipDescendants() }
            else if p.isDirectory != true { sum += Int64(p.fileSize ?? 0) }
        }
    }
    return sum
}

final class Store: ObservableObject {
    @Published var page: Page = .home
    @Published var files: [Item] = []
    @Published var picked: Set<String> = []
    @Published var busy = false
    @Published var notice = "準備就緒"
    @Published var records = HistoryStore.load()
    @Published var chosenApp: URL?
    @Published var diskRoot = FileManager.default.homeDirectoryForCurrentUser
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var memory: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var moleText = "Mole CLI 只會執行 --dry-run，不會真正刪除。"
    init() { metrics() }
    func metrics() {
        let a = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        diskFree = (a?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        diskTotal = (a?[.systemSize] as? NSNumber)?.int64Value ?? 0
    }
    func navigate(_ destination: Page) {
        page = destination; picked = []; files = []
        if [.clean,.apps,.disk].contains(destination) { scan() }
        if destination == .history { records = HistoryStore.load() }
    }
    func scan() {
        guard !busy else { return }
        busy = true; picked = []; notice = "掃描中…"
        let kind = page, root = diskRoot, selected = chosenApp
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
            var urls: [URL] = []
            switch kind {
            case .clean:
                for folder in ["Library/Caches","Library/Logs"] {
                    urls += (try? fm.contentsOfDirectory(at: home.appendingPathComponent(folder), includingPropertiesForKeys: nil)) ?? []
                }
            case .apps:
                for folder in [URL(fileURLWithPath:"/Applications"),home.appendingPathComponent("Applications")] {
                    urls += ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys:nil)) ?? []).filter { $0.pathExtension.lowercased() == "app" }
                }
            case .residual:
                if let app = selected { urls = ResidualScanner.candidates(for: app) }
            case .disk:
                urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys:nil)) ?? []
            default: break
            }
            let values = urls.filter { (try? $0.resourceValues(forKeys:[.isSymbolicLinkKey]))?.isSymbolicLink != true }
                .map { Item(url:$0,bytes:folderSize($0)) }.sorted { $0.bytes > $1.bytes }
            DispatchQueue.main.async {
                self.files = values; self.busy = false
                self.notice = "找到 \(values.count) 項；預設不選取，容量為估算。"
            }
        }
    }
    func trashSelected() {
        guard !busy, [.clean,.apps,.residual].contains(page) else { return }
        let list = files.filter { picked.contains($0.id) }
        guard !list.isEmpty else { return }
        let category = page
        busy = true
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser.path
            var success = 0, errors = 0
            for item in list {
                let path = item.url.standardizedFileURL.path
                let parent = item.url.deletingLastPathComponent().standardizedFileURL.path
                let safe: Bool
                switch category {
                case .clean:
                    safe = [home+"/Library/Caches",home+"/Library/Logs"].contains(parent)
                case .apps:
                    safe = item.url.pathExtension.lowercased() == "app" && ["/Applications",home+"/Applications"].contains(parent)
                case .residual:
                    safe = ResidualScanner.isAllowed(item.url)
                default: safe = false
                }
                guard safe, (try? item.url.resourceValues(forKeys:[.isSymbolicLinkKey]))?.isSymbolicLink != true else { errors += 1; continue }
                do {
                    var result: NSURL?
                    try fm.trashItem(at:item.url,resultingItemURL:&result)
                    if let location = result as URL? { HistoryStore.record(original:item.url,trash:location,category:category.rawValue) }
                    success += 1
                } catch { errors += 1 }
            }
            DispatchQueue.main.async {
                self.busy = false; self.notice = "移至垃圾桶 \(success) 項；失敗 \(errors) 項。"
                self.records = HistoryStore.load(); self.scan()
            }
        }
    }
    func restore(_ record: TrashRecord) {
        notice = HistoryStore.restore(record)
        records = HistoryStore.load()
    }
    func previewMole() {
        guard !busy else { return }
        guard let path = ["/usr/local/bin/mo","/opt/homebrew/bin/mo",NSHomeDirectory()+"/.local/bin/mo"].first(where: { FileManager.default.isExecutableFile(atPath:$0) }) else {
            moleText = "未有安裝官方 Mole CLI（tw93/Mole）。"; return
        }
        busy = true
        DispatchQueue.global(qos:.utility).async {
            let proc = Process(); proc.executableURL = URL(fileURLWithPath:path)
            proc.arguments = ["clean","--dry-run"]
            let pipe = Pipe(); proc.standardOutput = pipe; proc.standardError = pipe
            do {
                try proc.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                let output = String(data:data,encoding:.utf8) ?? "無可顯示輸出"
                DispatchQueue.main.async { self.moleText = String(output.prefix(30000)); self.busy = false }
            } catch {
                DispatchQueue.main.async { self.moleText = error.localizedDescription; self.busy = false }
            }
        }
    }
}

struct MainView: View {
    @StateObject private var store = Store()
    @State private var confirm = false
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                Text("MoleDesk").font(.title2).bold().padding(.bottom,14)
                ForEach(Page.allCases) { p in
                    Button(p.rawValue) { store.navigate(p) }.buttonStyle(.borderless)
                        .foregroundColor(store.page == p ? .accentColor : .primary).padding(.vertical,6)
                }
                Spacer()
                Text("v0.3 · Monterey Intel").font(.caption2).foregroundColor(.secondary)
            }.padding(18).frame(width:175,alignment:.leading).background(Color(NSColor.controlBackgroundColor))
            VStack(alignment:.leading,spacing:12) {
                Text(store.page.rawValue).font(.largeTitle).bold()
                if store.page == .home { home }
                else if store.page == .history { history }
                else if store.page == .mole { mole }
                else { listing }
                Spacer(minLength:0)
                Text(store.notice).font(.caption).foregroundColor(.secondary)
            }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }
        .frame(minWidth:870,minHeight:570)
        .alert(isPresented:$confirm) {
            Alert(title:Text("移到垃圾桶？"),message:Text("已選擇 \(store.picked.count) 項。請先核對路徑；App 殘留可能仍包含重要資料。"),
                  primaryButton:.destructive(Text("移到垃圾桶")) { store.trashSelected() },secondaryButton:.cancel())
        }
    }
    var home: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("記憶體：\(formatBytes(Int64(store.memory)))")
            Text("磁碟可用：\(formatBytes(store.diskFree)) / \(formatBytes(store.diskTotal))")
            if store.diskTotal > 0 {
                ProgressView(value:Double(store.diskTotal-store.diskFree),total:Double(store.diskTotal))
            }
            Text("系統摘要：磁碟容量及實體 RAM。CPU 數值將於後續版本加入。")
                .font(.caption).foregroundColor(.secondary)
            Button("更新數據") { store.metrics() }
        }.padding()
    }
    var listing: some View {
        VStack(alignment:.leading,spacing:10) {
            if store.page == .disk {
                HStack {
                    Text(store.diskRoot.path).font(.caption).lineLimit(1)
                    Button("選擇資料夾") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { store.diskRoot = url; store.scan() }
                    }
                }
            }
            if store.page == .residual {
                Text(store.chosenApp?.lastPathComponent ?? "請先選擇 App").font(.headline)
                Text("關聯只按名稱／Bundle ID 猜測，可能屬於共享資料。").font(.caption)
            }
            HStack {
                Button("重新掃描") { store.scan() }.disabled(store.busy)
                if store.page != .disk {
                    Button("移到垃圾桶 (\(store.picked.count))") { confirm = true }
                        .disabled(store.busy || store.picked.isEmpty)
                }
                if store.busy { ProgressView().scaleEffect(0.7) }
            }
            if store.page == .disk { diskBars }
            List(store.files) { item in
                HStack {
                    if store.page != .disk {
                        Toggle("",isOn:Binding(get:{store.picked.contains(item.id)},set:{ checked in
                            if checked { store.picked.insert(item.id) } else { store.picked.remove(item.id) }
                        })).labelsHidden()
                    }
                    VStack(alignment:.leading) {
                        Text(item.url.lastPathComponent).lineLimit(1)
                        Text(item.url.path).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(formatBytes(item.bytes)).font(.caption)
                    if store.page == .apps {
                        Button("殘留") { store.chosenApp = item.url; store.navigate(.residual); store.scan() }
                    }
                    if store.page == .disk {
                        Button("開啟") {
                            if (try? item.url.resourceValues(forKeys:[.isDirectoryKey]))?.isDirectory == true {
                                store.diskRoot = item.url; store.scan()
                            } else { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        }
                    }
                }
            }
        }
    }
    var diskBars: some View {
        let top = Array(store.files.prefix(8))
        let maximum = max(1,top.map{$0.bytes}.max() ?? 1)
        return VStack(spacing:4) {
            ForEach(Array(top.enumerated()),id:\.element.id) { index,entry in
                HStack {
                    Text(entry.url.lastPathComponent).lineLimit(1).frame(width:150,alignment:.leading)
                    GeometryReader { g in
                        Rectangle().fill(Color(hue:Double(index)/10,saturation:0.65,brightness:0.8))
                            .frame(width:max(1,g.size.width * CGFloat(Double(entry.bytes)/Double(maximum))))
                    }.frame(height:12)
                }
            }
        }.frame(height:CGFloat(top.count)*20)
    }
    var history: some View {
        List(store.records) { record in
            HStack {
                VStack(alignment:.leading) {
                    Text(URL(fileURLWithPath:record.original).lastPathComponent)
                    Text(record.original).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button(record.restored ? "已還原" : "還原") { store.restore(record) }
                    .disabled(record.restored || !FileManager.default.fileExists(atPath:record.trashed))
            }
        }
    }
    var mole: some View {
        VStack(alignment:.leading) {
            Text("官方 Mole 只讀預覽：不執行真正永久刪除。")
            Button("執行 dry-run") { store.previewMole() }.disabled(store.busy)
            ScrollView { Text(store.moleText).font(.system(.body,design:.monospaced)).textSelection(.enabled) }
        }
    }
}
