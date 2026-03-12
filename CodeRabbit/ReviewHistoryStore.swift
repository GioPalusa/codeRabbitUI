import Combine
import Foundation

struct ReviewHistoryItem: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let command: String
    let folderPath: String
    let rawOutput: String
    let findings: [ReviewFinding]
    let phases: [ReviewPhase]
    let statusLabel: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        command: String,
        folderPath: String,
        rawOutput: String,
        findings: [ReviewFinding],
        phases: [ReviewPhase],
        statusLabel: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.command = command
        self.folderPath = folderPath
        self.rawOutput = rawOutput
        self.findings = findings
        self.phases = phases
        self.statusLabel = statusLabel
    }
}

@MainActor
final class ReviewHistoryStore: ObservableObject {
    @Published private(set) var items: [ReviewHistoryItem] = []

    private let retentionDays = 30
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
        purgeExpired()
    }

    func add(
        id: UUID? = nil,
        createdAt: Date = Date(),
        command: String,
        folderPath: String,
        rawOutput: String,
        findings: [ReviewFinding],
        phases: [ReviewPhase],
        statusLabel: String
    ) {
        let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return }

        let item = ReviewHistoryItem(
            id: id ?? UUID(),
            createdAt: createdAt,
            command: command,
            folderPath: folderPath,
            rawOutput: rawOutput,
            findings: findings,
            phases: phases,
            statusLabel: statusLabel
        )

        items.insert(item, at: 0)
        purgeExpired()
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    func clearHistory(forFolderPath folderPath: String) {
        let normalizedTargetPath = normalizedFolderPath(folderPath)
        let filtered = items.filter { normalizedFolderPath($0.folderPath) != normalizedTargetPath }
        guard filtered.count != items.count else { return }
        items = filtered
        save()
    }

    func purgeExpired(referenceDate: Date = Date()) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: referenceDate) ?? referenceDate
        let filtered = items.filter { $0.createdAt >= cutoff }
        if filtered.count != items.count {
            items = filtered
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            items = []
            return
        }

        guard let decoded = try? decoder.decode([ReviewHistoryItem].self, from: data) else {
            items = []
            return
        }

        items = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        do {
            let data = try encoder.encode(items)
            try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("[ReviewHistoryStore] Failed to save history: \(error)")
        }
    }

    private var storageURL: URL {
        storageDirectoryURL.appendingPathComponent("review-history.json")
    }

    private var storageDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("CodeRabbit", isDirectory: true)
    }

    private func normalizedFolderPath(_ folderPath: String) -> String {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "/" : trimmed
    }
}
