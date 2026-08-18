import Foundation
import SwiftUI

/// One dataset that has been installed into the on-disk library. The metadata is
/// small and always kept in memory; the actual text/rows live in a sibling file and
/// are only read when a training run (or the user) actually needs them.
struct InstalledDataset: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case corpus, fineTune
        var id: String { rawValue }
        var label: String { self == .corpus ? "Pre-training" : "Fine-tuning" }
        var icon: String { self == .corpus ? "text.book.closed" : "tray.full" }
    }

    var id: UUID = UUID()
    var name: String
    var origin: String
    var kind: Kind
    var installedAt: Date = Date()
    /// File name inside the dataset's own folder ("data.txt" or "data.jsonl").
    var fileName: String
    var characters: Int = 0
    var rows: Int = 0
    var pairs: Int = 0
    var bytes: Int = 0

    var formattedSize: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    var summary: String {
        switch kind {
        case .corpus: return "\(characters.formatted()) characters · \(formattedSize)"
        case .fineTune: return "\(rows.formatted()) rows · \(pairs.formatted()) pairs · \(formattedSize)"
        }
    }
}

enum DatasetLibraryError: LocalizedError {
    case writeFailed(String)
    case readFailed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .writeFailed(let reason): return "Couldn't save that dataset to disk: \(reason)"
        case .readFailed(let reason): return "Couldn't read that installed dataset: \(reason)"
        case .empty: return "That dataset had no usable content, so nothing was installed."
        }
    }
}

/// The installed-dataset library. Every import — local file, Hugging Face file, or
/// Hugging Face Viewer rows — is written into Application Support so it survives a
/// relaunch instead of living only in memory for one session.
///
/// Layout:  ~/Library/Application Support/LabLLM/Library/<uuid>/{dataset.json,data.txt|data.jsonl}
@MainActor
final class DatasetLibrary: ObservableObject {
    @Published private(set) var datasets: [InstalledDataset] = []
    @Published var lastError: String?

    private var textCache: [UUID: String] = [:]
    private var conversationCache: [UUID: [[ChatMessage]]] = [:]

    init(load: Bool = true) { if load { reload() } }

    /// Redirects the library to a scratch folder. Tests set this so they never
    /// touch (or delete) the real installed data in Application Support.
    static var rootOverride: URL?

    static func rootDirectory() -> URL {
        let base = rootOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabLLM/Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func directory(for dataset: InstalledDataset) -> URL {
        Self.rootDirectory().appendingPathComponent(dataset.id.uuidString, isDirectory: true)
    }

    func fileURL(for dataset: InstalledDataset) -> URL {
        directory(for: dataset).appendingPathComponent(dataset.fileName)
    }

    func dataset(_ id: UUID) -> InstalledDataset? { datasets.first { $0.id == id } }

    func datasets(of kind: InstalledDataset.Kind) -> [InstalledDataset] {
        datasets.filter { $0.kind == kind }.sorted { $0.installedAt > $1.installedAt }
    }

    var totalBytes: Int { datasets.reduce(0) { $0 + $1.bytes } }

    // MARK: - Loading

    func reload() {
        let root = Self.rootDirectory()
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        datasets = folders.compactMap { folder -> InstalledDataset? in
            guard folder.hasDirectoryPath,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("dataset.json")),
                  let entry = try? decoder.decode(InstalledDataset.self, from: data),
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent(entry.fileName).path)
            else { return nil }
            return entry
        }.sorted { $0.installedAt > $1.installedAt }
    }

    // MARK: - Installing

    @discardableResult
    func installCorpus(name: String, origin: String, text: String) throws -> InstalledDataset {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DatasetLibraryError.empty }
        var entry = InstalledDataset(name: uniqueName(name), origin: origin, kind: .corpus, fileName: "data.txt",
                                     characters: text.count)
        let data = Data(text.utf8)
        entry.bytes = data.count
        // Line count doubles as the row count so a line limit can be estimated
        // without re-reading the file.
        entry.rows = text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        try write(entry: entry, payload: data)
        textCache[entry.id] = text
        datasets.insert(entry, at: 0)
        return entry
    }

    @discardableResult
    func installFineTune(name: String, origin: String, conversations: [[ChatMessage]]) throws -> InstalledDataset {
        guard !conversations.isEmpty else { throw DatasetLibraryError.empty }
        var entry = InstalledDataset(name: uniqueName(name), origin: origin, kind: .fineTune, fileName: "data.jsonl",
                                     rows: conversations.count,
                                     pairs: conversations.reduce(0) { $0 + ConversationImport.pairCount(in: $1) })
        let data = Data(Self.encodeJSONL(conversations).utf8)
        entry.bytes = data.count
        entry.characters = conversations.reduce(0) { $0 + $1.reduce(0) { $0 + $1.content.count } }
        try write(entry: entry, payload: data)
        conversationCache[entry.id] = conversations
        datasets.insert(entry, at: 0)
        return entry
    }

    private func write(entry: InstalledDataset, payload: Data) throws {
        let folder = directory(for: entry)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try payload.write(to: folder.appendingPathComponent(entry.fileName), options: .atomic)
            try metadata(entry).write(to: folder.appendingPathComponent("dataset.json"), options: .atomic)
        } catch { throw DatasetLibraryError.writeFailed(error.localizedDescription) }
    }

    private func metadata(_ entry: InstalledDataset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entry)
    }

    /// Keeps names distinct so the training mix stays readable when the same
    /// dataset is imported twice with different row limits.
    private func uniqueName(_ proposed: String) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled dataset" : proposed
        guard datasets.contains(where: { $0.name == base }) else { return base }
        var index = 2
        while datasets.contains(where: { $0.name == "\(base) (\(index))" }) { index += 1 }
        return "\(base) (\(index))"
    }

    // MARK: - Mutating

    func rename(_ dataset: InstalledDataset, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = datasets.firstIndex(of: dataset) else { return }
        var updated = dataset
        updated.name = uniqueName(trimmed)
        datasets[index] = updated
        do { try metadata(updated).write(to: directory(for: updated).appendingPathComponent("dataset.json"), options: .atomic) }
        catch { lastError = DatasetLibraryError.writeFailed(error.localizedDescription).localizedDescription }
    }

    func remove(_ dataset: InstalledDataset) {
        try? FileManager.default.removeItem(at: directory(for: dataset))
        datasets.removeAll { $0.id == dataset.id }
        textCache[dataset.id] = nil
        conversationCache[dataset.id] = nil
    }

    // MARK: - Reading content

    /// Full corpus text, read from disk on first use and cached afterwards.
    func text(for dataset: InstalledDataset) throws -> String {
        if let cached = textCache[dataset.id] { return cached }
        do {
            let text = try String(contentsOf: fileURL(for: dataset), encoding: .utf8)
            textCache[dataset.id] = text
            return text
        } catch { throw DatasetLibraryError.readFailed(error.localizedDescription) }
    }

    func conversations(for dataset: InstalledDataset) throws -> [[ChatMessage]] {
        if let cached = conversationCache[dataset.id] { return cached }
        do {
            let raw = try String(contentsOf: fileURL(for: dataset), encoding: .utf8)
            let parsed = ConversationImport.parseJSONL(raw)
            conversationCache[dataset.id] = parsed
            return parsed
        } catch { throw DatasetLibraryError.readFailed(error.localizedDescription) }
    }

    /// Drops cached content so a large mix doesn't stay resident after a run.
    func purgeCaches() {
        textCache.removeAll()
        conversationCache.removeAll()
    }

    static func encodeJSONL(_ conversations: [[ChatMessage]]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(conversations.count)
        for conversation in conversations {
            let messages = conversation.map { ["role": $0.role.rawValue, "content": $0.content] }
            guard let data = try? JSONSerialization.data(withJSONObject: ["messages": messages], options: []),
                  let line = String(data: data, encoding: .utf8) else { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
