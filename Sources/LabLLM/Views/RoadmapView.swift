import SwiftUI

/// A complete product map, grouped so the ambitious feature list remains usable.
struct RoadmapView: View {
    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let status: Status
        let features: [String]
        enum Status: Hashable { case built, inProgress, planned }
    }

    @State private var query = ""

    private let groups: [Group] = [
        .init(title: "Core App", status: .built, features: ["Local-first macOS app", "Apple Silicon + MLX acceleration", "Offline local project/model/dataset storage", "No account or subscription", "Light, dark, and custom themes", "Keyboard shortcuts, command palette, search, notifications", "Onboarding, Simple, Advanced, Expert modes", "Automatic updates and opt-in crash reporting"]),
        .init(title: "Model Workspaces", status: .inProgress, features: ["Create, rename, duplicate, switch, and delete models from the top-left model menu", "Per-model architecture, hyperparameters, tokenizer choice and training data mix, saved to disk", "Per-model run sessions: loss curves, metrics and sample timelines restored on launch", "Per-model checkpoint folders so saved runs never mix between models", "Model notes, tags, archiving, import/export and templates", "Versioning, snapshots, automatic/manual backups, restore", "Reproducible project packages"]),
        .init(title: "Model Builder", status: .built, features: ["GPT decoder architecture, presets from tiny to large", "Layers, hidden size, attention, KV heads, FFN, context, vocabulary", "Parameter, memory, disk, training-time and inference estimates", "Activation, normalization, RoPE, weight tying, bias, initialization, precision", "Validation, configuration preview/export", "Custom architecture and architecture visualization"]),
        .init(title: "Recipes", status: .inProgress, features: ["Runnable recipes that set architecture, hyperparameters and tokenizer in one click", "Recipes install the dataset they need and open Training ready to start", "Prerequisite and estimated-runtime reporting per recipe", "Recipe chaining across pretraining, SFT and DPO", "Custom and shared recipes"]),
        .init(title: "Tokenizer Lab", status: .inProgress, features: ["Character, byte, and BPE tokenizers", "WordPiece and Unigram", "Vocabulary and special-token editor", "Token visualization, probabilities, counts, compression and statistics", "Tokenizer testing, comparison, import/export", "Unicode, multilingual, and heatmap analysis"]),
        .init(title: "Dataset Studio", status: .inProgress, features: ["Dataset browser with infinite scroll, filters for purpose, size, language and popularity, and sorting", "Installed dataset library saved to disk and reloaded on launch", "Dataset cards rendered from real READMEs with frontmatter stripped and HTML flattened", "Recommended datasets pinned first in every mode", "Rename, reveal, and delete installed datasets; per-dataset size and provenance", "Versioning, snapshots, checksums, duplication", "Splitting, train/validation/test, sampling, balancing, curriculum", "TXT, JSON, JSONL, CSV, Markdown, HTML, PDF, folders, drag-and-drop", "Hugging Face, custom, conversation, instruction, preference, code and math imports"]),
        .init(title: "Data Quality", status: .planned, features: ["Exact and near-duplicate detection", "Normalization, encoding, HTML and boilerplate cleanup", "URL, spam, repetition, length, language, toxicity and PII filtering", "Quality scoring, custom/regex filters, before/after preview", "Document/token/character statistics, distributions, diversity and vocabulary coverage", "Histograms and charts"]),
        .init(title: "Curated Datasets", status: .inProgress, features: ["Built-in pretraining, instruction, conversation, math, coding, reasoning and preference datasets", "Descriptions, licenses, metadata, download manager, cache and update notices"]),
        .init(title: "Training", status: .built, features: ["Pretraining, SFT, LoRA, QLoRA, adapters, DPO", "Per-run dataset selection and mixing in the Training page, weighted by percentage or row limit", "Dataset/model/tokenizer selection", "Batching, accumulation, learning rate, scheduler, warmup, optimizer, clipping, dropout", "Epoch/step/sequence controls, mixed precision, memory optimization", "Pause, resume, stop, cancel, automatic checkpoints", "Live loss, validation, perplexity, LR, throughput, ETA, memory, hardware and event log", "Live samples and chronological sample timeline for pretraining and fine-tuning"]),
        .init(title: "Experiments and Checkpoints", status: .inProgress, features: ["Model-scoped checkpoint browser: each model lists only its own saved runs", "Automatic/manual checkpoints, rename, duplicate, delete, reveal, best detection", "Experiment metadata, tags, notes, hyperparameter/data/model/tokenizer/hardware tracking", "Comparison, duplication, reruns, leaderboards, export", "Checkpoint timeline, preview, restore, favorites, model-evolution timeline"]),
        .init(title: "Sampling and X-Ray", status: .inProgress, features: ["Streaming text generation, greedy, temperature, top-k, top-p, min-p, repetition penalty, seed, stop sequences", "Multiple generations, history, export, token probabilities, log probabilities, entropy", "Inline blue sampled text, continuation, generation comparison", "Token-level analysis, top candidates, rejected tokens, traces and playback", "Attention, layer/head, hidden-state, activation, residual, MLP and neuron explorers"]),
        .init(title: "Fine-tuning and Chat", status: .built, features: ["SFT wizard, instruction, conversation, completion, classification and custom tuning", "Chat templates, system/user/assistant roles, validation, masking, packing", "Fine-tuning checkpoints, evaluation, comparison, resume", "Local chat, histories, folders, editing, regeneration, continuation, system prompts, templates, context trimming and branching", "DPO preferences, rankings, labeling, statistics, beta, checkpoints, win-rate and leaderboard"]),
        .init(title: "Evaluation and Comparison", status: .planned, features: ["Automatic/manual perplexity, reasoning, math, coding, conversation, instruction, long-context, hallucination, consistency and safety evaluations", "Custom datasets/prompts/templates, history, leaderboard, scorecards and before/after", "Evaluation builder with exact, semantic, judge, regex and custom scoring", "Model/checkpoint/architecture/dataset/tokenizer comparison, blind side-by-side voting and benchmarks"]),
        .init(title: "Exploration Labs", status: .planned, features: ["Embedding explorer with similarity, neighbors, PCA, UMAP, t-SNE, clustering and export", "Attention, Transformer, Context, KV Cache, Prompt and RAG labs", "Tool/function calling schemas, simulator, evaluation and training", "Safety testing and reports", "Scaling laws, break-the-model experiments, model evolution"]),
        .init(title: "Model Import, Export, Quantization", status: .inProgress, features: ["Safetensors, compatible Hugging Face, local, tokenizer, configuration, LoRA and fine-tuned model import", "Validation, compatibility checks, conversion", "Safetensors/tokenizer/configuration/LoRA/quantized exports, recipes, cards and reproducibility packages", "FP32, FP16, BF16, INT8 and INT4 quantization, memory/speed/quality comparison and benchmarking", "Quantized model sampling and benchmarking"]),
        .init(title: "Hardware, Serving, Monitoring", status: .inProgress, features: ["Apple Silicon, chip, RAM, CPU, GPU, Neural Engine, thermal and power profiling", "Recommended model/batch sizes and speed estimates", "Training/memory/disk/compute estimators and scenario comparison", "OpenAI-compatible local server, streaming inference, endpoints, switching, request logs, token/latency statistics", "Inference monitoring, errors, health and performance history"]),
        .init(title: "Education and Assistance", status: .inProgress, features: ["Interactive textbook: fundamentals through safety", "Diagrams, simulations, sliders, quizzes, exercises, hints, projects, progress and history", "Hands-on onboarding tutorial", "Local AI tutor for concepts, errors, curves, recommendations and experiment review", "Smart training warnings and optimization suggestions", "Tiny GPT, Shakespeare, story, chat, math, coding, DPO, RAG and educational recipes"]),
        .init(title: "Reproducibility and Automation", status: .planned, features: ["Seeds, dataset/tokenizer/model/hyperparameter/hardware/software/MLX/macOS tracking", "Commands, hashes, checksums, reports and one-click reproduction", "Version control for models, datasets, tokenizers, experiments, prompts and evaluations", "Pipelines, multi-stage pretrain/SFT/DPO, scheduled/batch experiments, sweeps, grid/random search and ranking"]),
        .init(title: "Community, Collaboration, Future", status: .planned, features: ["Model, dataset, recipe, experiment and evaluation sharing", "Gallery, forks, ratings, comments, public benchmarks and leaderboards", "Shared projects, workspaces, comments, review and approvals", "Multimodal image, vision-language, audio, speech and voice workflows", "Python API, CLI, REST/WebSocket SDK, auth, docs and examples", "Natural-language model/recipe creation, visual research notebook, drag-and-drop builders and one-click deployment"]),
        .init(title: "UX, Accessibility, Docs, Privacy", status: .inProgress, features: ["Modern dashboard, resizable panels, split views, tabs, menus, tooltips, charts, fullscreen, favorites and pinned items", "Empty-state tutorials, error explanations and undo/redo", "Keyboard, screen reader, contrast, font, reduced motion, color-blind, accessible labels/tooltips and voice navigation", "Built-in searchable documentation, troubleshooting, glossary and explanations", "Local storage, privacy controls, deletion, telemetry transparency, offline indicator", "Secure storage, safe loading, validation, sandboxing, authentication and import safety"]),
        .init(title: "Ultimate Flow", status: .planned, features: ["Learn → Explore → Create → Design → Tokenize → Import → Clean → Analyze → Train → Inspect → Evaluate → Fine-tune → DPO → Compare → Quantize → Benchmark → Chat → RAG → Test Safety → Export → Serve → Share → Reproduce → Experiment"]),
    ]

    private var filtered: [Group] {
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            group.title.localizedCaseInsensitiveContains(query) || group.features.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var statusOrder: [Group.Status] { [.built, .inProgress, .planned] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkbenchPageHeader(eyebrow: "System", title: "Roadmap", subtitle: "The complete product direction, grouped by capability and honest implementation status.", icon: "map")
                TextField("Search capabilities", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                ForEach(statusOrder, id: \.self) { status in
                    let sectionGroups = filtered.filter { $0.status == status }
                    if !sectionGroups.isEmpty {
                        Text(sectionTitle(for: status)).font(.caption.weight(.bold)).foregroundStyle(color(for: status)).padding(.top, 8)
                        ForEach(sectionGroups) { group in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 7) {
                                    ForEach(group.features, id: \.self) { feature in
                                        Label(feature, systemImage: icon(for: group.status)).font(.callout).foregroundStyle(color(for: group.status))
                                    }
                                }.padding(.top, 8)
                            } label: {
                                HStack {
                                    Image(systemName: icon(for: group.status)).foregroundStyle(color(for: group.status))
                                    Text(group.title).font(.headline)
                                    Spacer()
                                    Text(label(for: group.status)).font(.caption.bold()).foregroundStyle(color(for: group.status))
                                }
                            }
                            .padding(12)
                            .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius))
                        }
                    }
                }
            }.padding(WorkbenchTheme.pagePadding)
        }
    }

    private func icon(for status: Group.Status) -> String { status == .built ? "checkmark.circle.fill" : status == .inProgress ? "clock.arrow.circlepath" : "circle.dashed" }
    private func color(for status: Group.Status) -> Color { status == .built ? .green : status == .inProgress ? .orange : .secondary }
    private func label(for status: Group.Status) -> String { status == .built ? "Built" : status == .inProgress ? "In progress" : "Planned" }
    private func sectionTitle(for status: Group.Status) -> String { status == .built ? "COMPLETED" : status == .inProgress ? "IN PROGRESS" : "PLANNED" }
}
