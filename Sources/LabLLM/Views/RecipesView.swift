import SwiftUI

/// Recipes as a launcher, not a gallery of presets. Picking one shows exactly what
/// it will do — the architecture, the hyperparameters, the dataset it needs and
/// whether that data is already installed — and starting it sets all of that up
/// and drops you on the Training page ready to run.
struct RecipesView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var library: DatasetLibrary
    @EnvironmentObject var models: ModelStore
    @EnvironmentObject var trainer: Trainer

    @State private var selected: Recipe = Recipe.all[0]

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchPageHeader(eyebrow: "Build", title: "Recipes",
                                subtitle: "Complete runs you can start in one click: model, hyperparameters, tokenizer and the data they need.",
                                icon: "wand.and.stars")
                .padding(.horizontal, WorkbenchTheme.pagePadding).padding(.top, 22).padding(.bottom, 14)
            GeometryReader { proxy in
                let listWidth = min(320, max(230, proxy.size.width * 0.32))
                HStack(spacing: 0) {
                    recipeList.frame(width: listWidth).frame(maxHeight: .infinity)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var recipeList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Recipe.all) { recipe in
                    row(recipe)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = recipe }
                }
            }
            .padding(12)
        }
        .background(WorkbenchTheme.panel)
    }

    private func row(_ recipe: Recipe) -> some View {
        let isSelected = recipe.id == selected.id
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: recipe.icon)
                .foregroundStyle(isSelected ? Color.white : WorkbenchTheme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(recipe.mode.label)
                    Text("·")
                    Text(recipe.timeTag)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? WorkbenchTheme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }

    // MARK: - Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let status = state.recipeStatus {
                    Label(status, systemImage: "sparkles")
                        .font(.callout).foregroundStyle(WorkbenchTheme.accent)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkbenchTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                }
                watchPanel
                dataPanel
                configPanel
                prerequisitePanel
            }
            .padding(WorkbenchTheme.pagePadding)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected.icon).font(.title).foregroundStyle(WorkbenchTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.name).font(.title2.bold())
                    Text(selected.summary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                WorkbenchPill(text: selected.mode.label)
                WorkbenchPill(text: selected.shapeTag)
                WorkbenchPill(text: selected.contextTag)
                WorkbenchPill(text: selected.stepsTag)
                WorkbenchPill(text: selected.timeTag)
            }
            HStack(spacing: 10) {
                Button("Set up in \(models.activeName)") { state.run(selected, inNewModel: false) }
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
                Button("Set up in a new model") { state.run(selected, inNewModel: true) }
                    .buttonStyle(WorkbenchSecondaryButtonStyle())
                Spacer()
            }
            Text("Applying a recipe replaces this model's hyperparameters and its \(selected.data.kind == .corpus ? "pre-training" : "fine-tuning") mix, then opens Training.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var watchPanel: some View {
        GroupBox("What to watch") {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "eye").foregroundStyle(.yellow)
                Text(selected.watchFor).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var dataPanel: some View {
        let installed = state.installedDataset(for: selected)
        return GroupBox("Data this recipe needs") {
            HStack(spacing: 12) {
                Image(systemName: selected.data.kind.icon).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.data.title).font(.callout.weight(.semibold))
                    Text("\(selected.data.repo) · \(selected.data.approximateSize)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.green)
                        .help(installed.summary)
                } else {
                    Label("Downloads on start", systemImage: "arrow.down.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var configPanel: some View {
        GroupBox("Exact configuration it applies") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                WorkbenchMetric(label: "Layers", value: "\(selected.gpt.nLayers)")
                WorkbenchMetric(label: "Hidden", value: "\(selected.gpt.nEmbd)")
                WorkbenchMetric(label: "Heads", value: "\(selected.gpt.nHeads)")
                WorkbenchMetric(label: "Context", value: "\(selected.gpt.blockSize)")
                WorkbenchMetric(label: "Batch", value: "\(selected.train.batchSize)")
                WorkbenchMetric(label: "Steps", value: selected.train.maxSteps.formatted())
                WorkbenchMetric(label: "Learning rate", value: String(format: "%.0e", selected.train.learningRate))
                WorkbenchMetric(label: "Tokenizer", value: selected.tokenizer.label)
            }
        }
    }

    @ViewBuilder private var prerequisitePanel: some View {
        if selected.needsTrainedModel {
            let ready = trainer.hasModel || !Checkpoint.list().isEmpty
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ready ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ready ? "Ready: this model has a checkpoint to fine-tune from."
                               : "Pretrain first — fine-tuning needs a trained model.")
                        .font(.callout.weight(.medium))
                    Text(ready ? "Pick the checkpoint to continue from in Training's resume menu."
                               : "Run a pre-training recipe for this model first, then come back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background((ready ? Color.green : Color.orange).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        }
    }
}
