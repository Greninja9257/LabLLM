import Foundation
import Testing
@testable import LabLLM

/// Installed datasets and model workspaces are real files on disk. These tests run
/// against a scratch root so they prove the round-trip without touching the user's
/// Application Support folder.
@MainActor
struct PersistenceTests {
    private func scratchRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LabLLMTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func installedCorpusSurvivesAReload() throws {
        let root = scratchRoot()
        DatasetLibrary.rootOverride = root
        defer { DatasetLibrary.rootOverride = nil; try? FileManager.default.removeItem(at: root) }

        let library = DatasetLibrary(load: false)
        let entry = try library.installCorpus(name: "Tiny corpus", origin: "Unit test", text: "line one\nline two\nline three")
        #expect(entry.characters == 28)
        #expect(entry.rows == 3)

        let reopened = DatasetLibrary()
        let restored = try #require(reopened.dataset(entry.id))
        #expect(restored.name == "Tiny corpus")
        #expect(restored.kind == .corpus)
        #expect(try reopened.text(for: restored) == "line one\nline two\nline three")
    }

    @Test func installedFineTuneRowsRoundTripThroughJSONL() throws {
        let root = scratchRoot()
        DatasetLibrary.rootOverride = root
        defer { DatasetLibrary.rootOverride = nil; try? FileManager.default.removeItem(at: root) }

        let conversations: [[ChatMessage]] = [
            [ChatMessage(role: .user, content: "hi"), ChatMessage(role: .assistant, content: "hello")],
            [ChatMessage(role: .system, content: "be terse"),
             ChatMessage(role: .user, content: "2+2?"), ChatMessage(role: .assistant, content: "4")]
        ]
        let library = DatasetLibrary(load: false)
        let entry = try library.installFineTune(name: "Chats", origin: "Unit test", conversations: conversations)
        #expect(entry.rows == 2)
        #expect(entry.pairs == 2)

        let restored = try #require(DatasetLibrary().dataset(entry.id))
        let reloaded = try DatasetLibrary().conversations(for: restored)
        #expect(reloaded.count == 2)
        #expect(reloaded[1].map(\.role) == [.system, .user, .assistant])
        #expect(reloaded[1][2].content == "4")
    }

    @Test func uninstallRemovesTheFilesFromDisk() throws {
        let root = scratchRoot()
        DatasetLibrary.rootOverride = root
        defer { DatasetLibrary.rootOverride = nil; try? FileManager.default.removeItem(at: root) }

        let library = DatasetLibrary(load: false)
        let entry = try library.installCorpus(name: "Temp", origin: "Unit test", text: "text")
        let folder = library.directory(for: entry)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        library.remove(entry)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(DatasetLibrary().datasets.isEmpty)
    }

    @Test func eachModelGetsItsOwnCheckpointFolder() {
        let root = scratchRoot()
        ModelStore.rootOverride = root
        defer {
            ModelStore.rootOverride = nil
            Checkpoint.activeModelDirectory = nil
            try? FileManager.default.removeItem(at: root)
        }

        let store = ModelStore()
        let first = try! #require(store.active)
        let second = store.create(named: "Second model")

        store.select(first.id)
        let firstDirectory = Checkpoint.directory()
        store.select(second.id)
        let secondDirectory = Checkpoint.directory()

        #expect(firstDirectory != secondDirectory)
        #expect(firstDirectory.path.hasPrefix(root.path))
        #expect(secondDirectory.path.hasPrefix(root.path))
        #expect(store.checkpointCount(for: second.id) == 0)
    }

    @Test func workspaceConfigurationIsPersisted() {
        let root = scratchRoot()
        ModelStore.rootOverride = root
        defer { ModelStore.rootOverride = nil; Checkpoint.activeModelDirectory = nil; try? FileManager.default.removeItem(at: root) }

        let store = ModelStore()
        var workspace = store.active!
        workspace.name = "Configured"
        workspace.gptConfig.nLayers = 11
        workspace.trainConfig.maxSteps = 1234
        workspace.corpusMix = [DatasetSelection(datasetID: UUID(), isEnabled: true, limitMode: .lines, percent: 50, lineLimit: 42)]
        store.save(workspace)

        let reopened = ModelStore()
        let restored = reopened.models.first { $0.id == workspace.id }
        #expect(restored?.name == "Configured")
        #expect(restored?.gptConfig.nLayers == 11)
        #expect(restored?.trainConfig.maxSteps == 1234)
        #expect(restored?.corpusMix.first?.lineLimit == 42)
        #expect(restored?.corpusMix.first?.limitMode == .lines)
    }

    @Test func trainingSessionsRoundTripPerModeAndModel() {
        let root = scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var pretrain = TrainingSession(mode: .pretrain, method: "Pretraining", datasetName: "Tiny Shakespeare",
                                       step: 500, maxSteps: 500, trainLoss: 1.42, valLoss: 1.61, completed: true)
        pretrain.lossHistory = [.init(step: 1, value: 4.2, isValidation: false),
                                .init(step: 100, value: 2.1, isValidation: false),
                                .init(step: 100, value: 2.3, isValidation: true)]
        pretrain.samples = [.init(step: 100, text: "to be or not", method: "Pretraining", createdAt: Date())]
        let sft = TrainingSession(mode: .sft, method: "SFT (LoRA)", step: 200, maxSteps: 800, trainLoss: 0.9)

        TrainingSessionStore.save([.pretrain: pretrain, .sft: sft], to: root)
        let restored = TrainingSessionStore.load(from: root)

        #expect(restored.count == 2)
        #expect(restored[.pretrain]?.lossHistory.count == 3)
        #expect(restored[.pretrain]?.lossHistory.last?.isValidation == true)
        #expect(restored[.pretrain]?.samples.first?.text == "to be or not")
        #expect(restored[.pretrain]?.completed == true)
        #expect(restored[.sft]?.method == "SFT (LoRA)")
        #expect(restored[.dpo] == nil)
    }

    @Test func missingSessionFileIsNotAnError() {
        let root = scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TrainingSessionStore.load(from: root).isEmpty)
    }

    @Test func trainerRestoresASavedDashboard() {
        var session = TrainingSession(mode: .sft, method: "SFT (LoRA)", datasetName: "Chats",
                                      step: 420, maxSteps: 800, trainLoss: 1.1, valLoss: 1.3, runIsLoRA: true)
        session.lossHistory = [.init(step: 10, value: 3.0, isValidation: false),
                               .init(step: 20, value: 2.5, isValidation: true)]
        session.samples = [.init(step: 20, text: "hello there", method: "SFT (LoRA)", createdAt: Date())]

        let trainer = Trainer()
        trainer.restore(session: session)

        #expect(trainer.step == 420)
        #expect(trainer.runMode == .sft)
        #expect(trainer.runIsLoRA)
        #expect(trainer.lossHistory.count == 2)
        #expect(trainer.lossHistory.last?.kind == .val)
        #expect(trainer.sampleHistory.first?.text == "hello there")
        #expect(trainer.liveSample == "hello there")

        trainer.clearSession(mode: .pretrain)
        #expect(trainer.step == 0)
        #expect(trainer.lossHistory.isEmpty)
        #expect(trainer.runMode == .pretrain)
    }

    @Test func selectionLimitsAreComputedFromMetadata() {
        let dataset = InstalledDataset(name: "D", origin: "test", kind: .fineTune, fileName: "data.jsonl",
                                       characters: 1_000, rows: 200, pairs: 400, bytes: 1_000)
        let half = DatasetSelection(datasetID: dataset.id, limitMode: .percent, percent: 50)
        #expect(half.selectedRows(in: dataset) == 100)
        #expect(half.selectedPairs(in: dataset) == 200)

        let capped = DatasetSelection(datasetID: dataset.id, limitMode: .lines, lineLimit: 50)
        #expect(capped.selectedRows(in: dataset) == 50)
        #expect(capped.selectedCharacters(in: dataset) == 250)

        let overshoot = DatasetSelection(datasetID: dataset.id, limitMode: .lines, lineLimit: 10_000)
        #expect(overshoot.selectedRows(in: dataset) == 200)
    }
}
