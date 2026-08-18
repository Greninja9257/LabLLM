import Foundation
import SwiftUI

/// One installed dataset's share of a training mix. Mixing lives with the model
/// (and therefore with the run you are about to start), not with the dataset
/// browser, so switching models switches the data recipe too.
struct DatasetSelection: Codable, Identifiable, Equatable {
    var datasetID: UUID
    var isEnabled: Bool = true
    var limitMode: DatasetLimitMode = .percent
    var percent: Double = 100
    var lineLimit: Int = 1_000

    var id: UUID { datasetID }

    /// How many rows (fine-tuning) or lines (pre-training) this selection keeps.
    func selectedCount(of total: Int) -> Int {
        guard total > 0 else { return 0 }
        switch limitMode {
        case .percent: return min(total, max(1, Int((Double(total) * percent / 100).rounded())))
        case .lines: return min(total, max(0, lineLimit))
        }
    }

}

extension DatasetSelection {
    /// Characters this selection contributes, estimated from stored metadata so
    /// summaries never have to read a multi-hundred-megabyte file.
    func selectedCharacters(in dataset: InstalledDataset) -> Int {
        switch limitMode {
        case .percent:
            return min(dataset.characters, max(0, Int((Double(dataset.characters) * percent / 100).rounded())))
        case .lines:
            guard dataset.rows > 0 else { return dataset.characters }
            let share = Double(min(lineLimit, dataset.rows)) / Double(dataset.rows)
            return min(dataset.characters, Int((Double(dataset.characters) * share).rounded()))
        }
    }

    func selectedRows(in dataset: InstalledDataset) -> Int { selectedCount(of: dataset.rows) }

    func selectedPairs(in dataset: InstalledDataset) -> Int {
        guard dataset.rows > 0 else { return 0 }
        let share = Double(selectedRows(in: dataset)) / Double(dataset.rows)
        return Int((Double(dataset.pairs) * share).rounded())
    }
}

/// A named model in the studio: its architecture, hyperparameters, tokenizer choice,
/// data mix, and its own checkpoint folder. Everything the top-left model menu
/// switches between.
struct ModelWorkspace: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var gptConfig = GPTConfig()
    var trainConfig = TrainConfig()
    var tokenizerKind: TokenizerKind = .character
    var bpeTargetVocab: Int = 800
    var corpusMix: [DatasetSelection] = []
    var fineTuneMix: [DatasetSelection] = []
}

/// Owns every model workspace on disk and tracks which one is active. Checkpoints
/// are stored inside the active model's folder, so the Checkpoints browser only
/// ever shows runs that belong to the model you are working on.
///
/// Layout:  ~/Library/Application Support/LabLLM/Models/<uuid>/{model.json,Checkpoints/}
@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var models: [ModelWorkspace] = []
    @Published private(set) var activeID: UUID?
    @Published var lastError: String?

    private let activeKey = "labllm.activeModelID"

    init(load: Bool = true) {
        guard load else { return }
        reload()
        migrateLegacyCheckpointsIfNeeded()
        if models.isEmpty { _ = create(named: "My First Model") }
        let stored = UserDefaults.standard.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        activeID = models.contains(where: { $0.id == stored }) ? stored : models.first?.id
        syncCheckpointDirectory()
    }

    /// Redirects model storage to a scratch folder. Tests set this so they never
    /// touch (or delete) the real models in Application Support.
    static var rootOverride: URL?

    static func rootDirectory() -> URL {
        let base = rootOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabLLM/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func directory(for id: UUID) -> URL {
        Self.rootDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    var active: ModelWorkspace? { models.first { $0.id == activeID } }

    var activeName: String { active?.name ?? "No model" }

    func checkpointCount(for id: UUID) -> Int {
        let dir = directory(for: id).appendingPathComponent("Checkpoints", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.hasDirectoryPath }.count
    }

    // MARK: - Persistence

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.rootDirectory(), includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        models = folders.compactMap { folder -> ModelWorkspace? in
            guard folder.hasDirectoryPath,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("model.json")) else { return nil }
            return try? decoder.decode(ModelWorkspace.self, from: data)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ workspace: ModelWorkspace) {
        var updated = workspace
        updated.updatedAt = Date()
        if let index = models.firstIndex(where: { $0.id == updated.id }) { models[index] = updated }
        else { models.append(updated) }
        persist(updated)
    }

    private func persist(_ workspace: ModelWorkspace) {
        let folder = directory(for: workspace.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Checkpoints", isDirectory: true),
                                                    withIntermediateDirectories: true)
            try encoder.encode(workspace).write(to: folder.appendingPathComponent("model.json"), options: .atomic)
        } catch {
            lastError = "Couldn't save model '\(workspace.name)': \(error.localizedDescription)"
        }
    }

    // MARK: - Model management

    @discardableResult
    func create(named name: String) -> ModelWorkspace {
        let workspace = ModelWorkspace(name: uniqueName(name))
        models.append(workspace)
        persist(workspace)
        return workspace
    }

    func select(_ id: UUID) {
        guard models.contains(where: { $0.id == id }) else { return }
        activeID = id
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        syncCheckpointDirectory()
    }

    func rename(_ id: UUID, to newName: String) {
        guard var workspace = models.first(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != workspace.name else { return }
        workspace.name = uniqueName(trimmed, excluding: id)
        save(workspace)
    }

    @discardableResult
    func duplicate(_ id: UUID) -> ModelWorkspace? {
        guard let source = models.first(where: { $0.id == id }) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name = uniqueName("\(source.name) copy")
        copy.createdAt = Date()
        models.append(copy)
        persist(copy)
        // Carry the run history across so a duplicate is a real branch point.
        let from = directory(for: source.id).appendingPathComponent("Checkpoints", isDirectory: true)
        let to = directory(for: copy.id).appendingPathComponent("Checkpoints", isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) {
            for item in contents where item.hasDirectoryPath {
                try? FileManager.default.copyItem(at: item, to: to.appendingPathComponent(item.lastPathComponent))
            }
        }
        return copy
    }

    func delete(_ id: UUID) {
        guard models.count > 1 else {
            lastError = "Keep at least one model. Create another model before deleting this one."
            return
        }
        try? FileManager.default.removeItem(at: directory(for: id))
        models.removeAll { $0.id == id }
        if activeID == id, let next = models.first?.id { select(next) }
    }

    private func uniqueName(_ proposed: String, excluding id: UUID? = nil) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled model" : proposed
        let taken = models.filter { $0.id != id }.map(\.name)
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    // MARK: - Checkpoint scoping

    private func syncCheckpointDirectory() {
        guard let activeID else { Checkpoint.activeModelDirectory = nil; return }
        Checkpoint.activeModelDirectory = directory(for: activeID)
    }

    /// Checkpoints used to live in one shared folder. On first launch after the
    /// model-workspace change, adopt them into a model so no run is orphaned.
    private func migrateLegacyCheckpointsIfNeeded() {
        // Never reach into the real Application Support folder from a scratch store.
        guard Self.rootOverride == nil else { return }
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabLLM/Checkpoints", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
        let runs = contents.filter { $0.hasDirectoryPath }
        guard !runs.isEmpty else { return }
        let target = models.first ?? create(named: "My First Model")
        let destination = directory(for: target.id).appendingPathComponent("Checkpoints", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for run in runs {
            try? FileManager.default.moveItem(at: run, to: destination.appendingPathComponent(run.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: legacy)
    }
}
