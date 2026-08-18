# LabLLM Roadmap

LabLLM is a native macOS workshop for building, training, fine-tuning, sampling, and inspecting small language models on Apple Silicon.

This roadmap is meant for GitHub visitors and contributors. It shows what already works, what is actively being hardened, and where help would make the biggest difference.

## Status Legend

| Mark | Meaning |
| --- | --- |
| ✅ | Built and usable in the beta |
| 🟡 | Partially built, being hardened, or needs polish |
| 🔵 | Good contributor project |
| ⚪ | Planned |

## Current Focus

| Priority | Area | Status | Notes |
| --- | --- | --- | --- |
| P0 | Training correctness | 🟡 | Determinism, fixed validation, checkpoint state, padding masks, dataset windowing, and DPO truncation are being treated as correctness-critical. |
| P0 | Reproducible experiments | 🟡 | New checkpoints store more training state. Older checkpoints load, but cannot exact-resume because they did not contain optimizer/RNG state. |
| P0 | Dataset reliability | 🟡 🔵 | Importing, previewing, filtering, chunking, and mixing data should be robust before new dataset features grow further. |
| P0 | Local persistence | 🟡 | Installed datasets are written to Application Support and reloaded on launch. Model workspaces and their checkpoints are stored per model. Import/export of a whole model is still missing. |
| P1 | Model workspaces | 🟡 🔵 | Each model owns its architecture, hyperparameters, tokenizer choice, data mix, checkpoints, and saved run sessions. Notes, tags, archiving, and comparison across models are still open. |
| P1 | Contributor test coverage | 🟡 🔵 | Core behavior tests exist and should expand around LoRA, DPO, tokenizer edge cases, and checkpoint compatibility. |
| P1 | UX clarity | 🟡 🔵 | The app should make training state, beta limitations, progress, errors, and next steps obvious. |

## Completed

| Area | What Works |
| --- | --- |
| Core app | Native macOS app, SwiftUI interface, local-first storage, no account requirement, dark/light/custom appearance controls. |
| Apple Silicon | MLX-backed training path, bundled MLX Metal library, hardware profiler, resource estimator. |
| Modes | Simple, Advanced, and Expert modes with feature visibility controls. |
| Model builder | GPT-style decoder configs, model presets, parameter estimates, memory/disk/time estimates, config validation. |
| Tokenizers | Character tokenizer, byte tokenizer, trained BPE tokenizer, Simple mode automatic tokenizer build. |
| Model workspaces | Named models created, renamed, duplicated, switched, and deleted from the model menu in the top-left of the sidebar. Each model stores its own architecture, hyperparameters, tokenizer choice, and data mix. |
| Data import | Local TXT, JSON, JSONL, CSV-ish data, iMessage import path, Hugging Face dataset browsing/import. |
| Installed dataset library | Every import is written to `~/Library/Application Support/LabLLM/Library` and reloaded on the next launch. Installed datasets can be renamed, revealed in Finder, and deleted from disk. |
| Dataset mixing | Percentage-based and row-limit mixing, configured per run in the Training page rather than in the dataset browsers. |
| Large-task handling | Download/import progress and chunked local file loading for bigger files. |
| Pretraining | AdamW/SGD, warmup, cosine LR, gradient clipping, gradient accumulation, checkpoints, pause, resume controls, stop controls. |
| Fine-tuning | SFT with chat templates and assistant-only loss masking, LoRA fine-tuning, DPO preference training. |
| Training dashboard | Train loss, orange validation loss, perplexity, learning rate, throughput, ETA, percent progress, live samples. |
| Sampling | Temperature, top-k, top-p, min-p, repetition penalty, seed, stop sequences, greedy mode, continuation, inline generation display. |
| Chat | Local model chat playground with streamed responses. |
| Inspection | X-Ray token probabilities, entropy, top alternatives, embedding explorer with 2D projection. |
| Session history | Loss curves, metrics, and sample timelines are saved per model and per run mode (pretrain, fine-tune, DPO), and restored automatically on relaunch. |
| Recipes | Runnable recipes that apply the architecture, hyperparameters and tokenizer, install the dataset they need, and open Training ready to start. |
| Dataset cards | Hugging Face READMEs are rendered with YAML frontmatter stripped and HTML flattened, instead of showing raw markup. |
| Checkpoints | Model-scoped checkpoint browser (each model lists only its own runs), save/load, rename/duplicate/delete flows, quantized export, Markdown model cards. |
| Serving | Local OpenAI-shaped HTTP server with streaming responses. |
| Onboarding | Welcome screen, persistent tutorial progress, guided setup overlay. |
| Community | README, website, issue templates, PR template, contributing guide, discussions guide, all-contributors support. |

## In Progress

| Area | Goal | Help Wanted |
| --- | --- | --- |
| Training resume | Make resume continue the real optimization trajectory, including optimizer state, step, scheduler position, RNG, and config. | 🔵 Tests against split-run vs continuous-run behavior. |
| Reproducibility | Ensure seeds control model init, dataset sampling, validation, dropout, and generation where practical. | 🔵 Determinism tests and clear docs for unavoidable MLX limits. |
| Validation | Keep validation on fixed held-out examples unless randomized eval is explicitly requested. | 🔵 More tests around SFT/DPO validation paths. |
| Dataset windowing | Cover empty, short, exact-size, padded, and final-window boundary cases. | 🔵 Small tests are very useful here. |
| Padding loss | Ensure padding never teaches the model to predict padding as language. | 🔵 More loss-mask tests across batches and SFT/DPO paths. |
| DPO correctness | Preserve chosen/rejected assistant responses under truncation and verify reference-model invariants. | 🔵 DPO tests are a high-impact contribution. |
| Tokenizer robustness | Handle unseen characters explicitly instead of silently mapping them to normal tokens. | 🔵 Good first Core correctness issue. |
| LoRA correctness | Verify zero-B initialization preserves outputs, only adapters train, base model stays frozen, and adapter save/load works. | 🔵 Strong contributor project for ML-minded folks. |
| Checkpoint browser | Surface whether a checkpoint is exact-resumable or legacy/incomplete. | 🔵 UI + metadata task. |
| Model workspaces | Notes, tags, archiving, model-to-model comparison, and export/import of a complete model folder. | 🔵 Good app-level contribution. |
| Dataset library | Checksums, licenses, versioning, dedupe on install, and re-import of a dataset that changed upstream. | 🔵 Data-quality contributors welcome. |
| Dataset Studio | Better filtering, sorting, provenance, previews, and caching. | 🔵 Frontend and data-quality contributors welcome. |
| Experiment history | Sessions currently keep the latest run per mode. Keeping a full run history, comparing runs, and exporting them is the next step. | 🔵 Natural follow-on to session persistence. |
| Recipes | More recipes, recipe sharing, and recipes that chain pretrain → SFT → DPO in one plan. | 🔵 Good contributor project. |
| Tutorial | More complete guided setup across Simple, Advanced, and Expert mode without forcing a single path. | 🔵 UX/content contribution. |
| Local server | Request logs, token usage, latency stats, model health, and safer local API controls. | 🔵 Practical app/backend work. |

## Planned

### Experiment Tracking

| Feature | Status |
| --- | --- |
| Experiment names, notes, tags, and descriptions | ⚪ |
| Hyperparameter, dataset, tokenizer, model, hardware, and software-version tracking | ⚪ |
| Experiment comparison and reruns | ⚪ |
| Experiment leaderboard/history/export | ⚪ |
| Reproducibility reports with hashes and environment metadata | ⚪ |

### Evaluation

| Feature | Status |
| --- | --- |
| Perplexity evaluation | ⚪ |
| Instruction-following tests | ⚪ |
| Conversation tests | ⚪ |
| Reasoning/math/coding tests | ⚪ |
| Custom evaluation datasets and prompts | ⚪ |
| Model scorecards and checkpoint evaluation | ⚪ |
| Evaluation reports and exports | ⚪ |

### Model Comparison

| Feature | Status |
| --- | --- |
| Compare checkpoints, architectures, datasets, tokenizers, and prompts | ⚪ |
| Same prompt across models | ⚪ |
| Side-by-side and blind comparison | ⚪ |
| Win-rate, quality, speed, memory, and context comparisons | ⚪ |

### Deeper Inspection Labs

| Lab | Planned Capabilities |
| --- | --- |
| X-Ray Mode | Attention, layers, heads, activations, residual stream, MLP, neuron explorer, generation trace playback. |
| Attention Lab | Head explorer, token-to-token attention, attention masks, score/softmax visualization. |
| Transformer Lab | Step-by-step forward pass, embeddings, self-attention, residuals, layer norm, MLP, output projection. |
| Context Lab | Context-window utilization, truncation visualization, KV-cache visualization, long-context testing. |
| Embedding Explorer | Similarity search, nearest neighbors, clustering, PCA/UMAP/t-SNE-style views, 3D visualization. |

### Data Quality

| Feature | Status |
| --- | --- |
| Duplicate and near-duplicate detection | ⚪ |
| Text normalization and encoding cleanup | ⚪ |
| HTML cleanup and boilerplate removal | ⚪ |
| Length/language/repetition filtering | ⚪ |
| PII detection/redaction | ⚪ |
| Data-quality scoring and before/after previews | ⚪ |
| Dataset analytics charts and histograms | ⚪ |

### Import / Export

| Feature | Status |
| --- | --- |
| Hugging Face model import compatibility checks | ⚪ |
| Safetensors export polish | ⚪ |
| LoRA adapter import/export | ⚪ |
| Tokenizer/config export | ⚪ |
| Complete project export | ⚪ |
| Reproducible project packages | ⚪ |
| PDF/Markdown reports | ⚪ |

### Automation

| Feature | Status |
| --- | --- |
| Multi-stage pipelines: pretraining -> SFT -> DPO | ⚪ |
| Automatic evaluation after training | ⚪ |
| Automatic checkpoint selection | ⚪ |
| Hyperparameter sweeps | ⚪ |
| Training recipes and recipe sharing | ⚪ |
| Natural-language experiment summaries | ⚪ |

### Research And Learning

| Feature | Status |
| --- | --- |
| Interactive lessons and textbook-style explanations | ⚪ |
| Quizzes, knowledge checks, practice exercises | ⚪ |
| Scaling law experiments | ⚪ |
| Break-the-model experiments | ⚪ |
| Smart training assistant | ⚪ |
| Local AI teaching assistant | ⚪ |

### Future Directions

| Area | Status |
| --- | --- |
| RAG workflows with local vector database and citations | ⚪ |
| Tool/function-calling lab | ⚪ |
| Safety testing workflows | ⚪ |
| Python API and CLI | ⚪ |
| SDK and WebSocket support | ⚪ |
| More complete local model serving | ⚪ |
| Community model/dataset/recipe sharing | ⚪ |
| Collaboration features | ⚪ |
| Multimodal and voice experiments | ⚪ |

## Suggested User Flow

```text
Learn
-> Explore
-> Create model
-> Design model
-> Install data
-> Clean/analyze data
-> Choose the training mix
-> Configure training
-> Estimate resources
-> Train
-> Watch samples evolve
-> Inspect checkpoints
-> Sample/chat
-> Fine-tune
-> DPO
-> Compare
-> Quantize
-> Serve locally
-> Reproduce
-> Keep experimenting
```

## Best Ways To Contribute

If you want to help, the highest-impact areas are:

1. **Core correctness tests**: dataset boundaries, padding masks, deterministic sampling, checkpoint resume, LoRA invariants, DPO reference behavior.
2. **Bug reports with reproduction steps**: exact macOS version, Mac model, dataset type, model config, and what happened.
3. **Dataset import improvements**: more formats, better previews, safer parsing, progress reporting, better errors.
4. **Tutorial and docs**: hands-on guides that help beginners train a first tiny model.
5. **SwiftUI polish**: clearer states, better empty states, accessibility, keyboard navigation, and better explanations when something fails.

Start here:

- [Contributing guide](CONTRIBUTING.md)
- [Issues](https://github.com/Greninja9257/LabLLM/issues)
- [Discussions](https://github.com/Greninja9257/LabLLM/discussions)
- [Latest beta releases](https://github.com/Greninja9257/LabLLM/releases)

## Roadmap Policy

This roadmap is intentionally ambitious, but correctness beats feature count.

New features should not make training less trustworthy. If a feature touches randomness, loss, masking, optimizer state, checkpoints, tokenization, LoRA, DPO, or dataset windowing, it needs tests that prove the behavior.
