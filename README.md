# LabLLM

A native **macOS (SwiftUI + Apple MLX)** app for training, fine-tuning, and serving small GPT language models locally on Apple Silicon.

---

## Read this first

This is a **real, buildable Xcode project**, written against the actual `mlx-swift` API (signatures verified by cloning and grepping the source), but it has **not been compiled or run** in this environment — no Xcode, no Apple Silicon, no Metal compiler available here. Everything below is implemented as real, working logic (not stubs), verified against the library's actual source wherever I could, but you are the first compiler it will meet. See **Spots to sanity-check first** below if the build complains.

Requirements: **Apple Silicon (M1+)**, **macOS 14+**, **Xcode 15+** (full Xcode — MLX needs the Metal compiler, which the Command Line Tools alone don't include).

## Build & run

1. Xcode → **File ▸ New ▸ Project ▸ macOS ▸ App** (SwiftUI). Delete the template `ContentView`/`App` files, drag in everything under `Sources/LabLLM/`.
2. **File ▸ Add Package Dependencies…** → `https://github.com/ml-explore/mlx-swift` (pinned here at `0.31.6`, which includes the fix for the `std::array` C++ build error some older versions hit) → add products **MLX, MLXNN, MLXOptimizers, MLXRandom, MLXFast**.
3. Build & run (⌘R). Keep **Swift Language Version = 5** (Xcode default) — see *Concurrency note*.

If your Xcode/mlx-swift version combination reports an incompatible-tools-version resolver error, try pinning to a slightly older mlx-swift release in the `0.25–0.31` range in Xcode's package rules.

---

## What's implemented

**Guided experience** — Simple/Advanced/Expert modes (persisted, feature-gated), a welcome flow, a replayable tutorial, loading overlays with status text.

**Model & tokenizers** — configurable GPT decoder with live estimates; **character, byte-level, and a real trained byte-pair-encoding (BPE) tokenizer** (GPT-2 style: byte→symbol mapping, iterative merge learning, greedy encode).

**Data** — TXT import for pretraining; **fine-tuning data import**: local JSONL (several schemas: `messages`, Alpaca-style `instruction/output`, `prompt/response`) with a real example-row preview, plus a best-effort **Hugging Face downloader** (editable repo/file path, since dataset layouts vary — errors surface clearly rather than failing silently) and a small curated catalog.

**Training** — pretraining, **SFT with assistant-only loss masking** (chat template with `<|system|>/<|user|>/<|assistant|>/<|end|>`), and **DPO** (frozen reference model + policy, real preference loss). AdamW/SGD, warmup+cosine LR, gradient accumulation/clipping, periodic checkpointing, **resume from any checkpoint**, pause/stop.

**LoRA** — real low-rank adapters on the Q/V attention projections, added via `freeze()` then attaching fresh trainable adapters (base weights excluded from gradients automatically since they were frozen before the adapters existed). Adapter-only weights are saved alongside the full merged checkpoint.

**Reliability** — training/checkpoint errors surface in the UI instead of failing silently; **Cmd+Q gracefully stops an active run and waits (up to 8s) for the in-flight checkpoint save** before quitting, via a proper `NSApplicationDelegate` with `.terminateLater`.

**Sampling & inspection** — temperature/top-k/top-p/min-p/repetition-penalty/stop-sequences/seed, streamed; a **chat playground**; an **X-Ray token inspector** showing each generated token's real probability, entropy, and top alternatives; a **local OpenAI-shaped HTTP server** (`/v1/chat/completions`, non-streaming) over the in-memory model.

**Embedding map** — a real PCA projection (power iteration + deflation, pure Swift) of the model's *trained* token embeddings into 2D, with an animated similarity-based relaxation pass so related tokens visibly drift together.

**Checkpoints** — safetensors + JSON + auto-generated Markdown **model card**; best-checkpoint flag by val loss; **quantization export** using MLX's native `quantize()` (real 4-bit/8-bit quantized weights, not a size estimate) with a before/after file-size comparison.

**Recipes, Estimator, Hardware profiler** — one-click setups, resource math, chip/RAM guidance.

## What's NOT built

Attention/hidden-state visualization (needs exposing intermediate activations), evaluation suites, experiment tracking/sweeps, multi-project management, the educational textbook, community features, multimodal/voice. See the in-app **Roadmap** tab (Expert mode) for the full breakdown.

Two specific things worth flagging even though the surrounding feature is real:
- **Quantized checkpoints aren't loadable back into the app yet.** Export works and produces genuine quantized weights + a real size comparison; wiring `QuantizedLinear`/`QuantizedEmbedding` back through `Checkpoint.loadModel` for sampling is the natural next step.
- **The local server doesn't actually stream** — a `stream: true` request still gets one complete response. True SSE streaming over the raw socket layer was cut to avoid guessing at more unverified plumbing.

---

## Spots to sanity-check first

I verified every MLX-Swift API used here against the cloned source, but I can't compile Swift or run Metal in this environment, so treat these as the highest-probability trouble spots if the build fails:

1. **LoRA's freeze/attach order** (`GPT.addLoRA`) — relies on `freeze()` snapshotting the *existing* module tree at call time, so adapters attached afterward stay trainable. This matches the documented behavior in MLX-Swift's own `Module.swift`, but it's the trickiest piece of new logic here.
2. **`valueAndGrad` with the `[MLXArray]` array-output overload** — used for SFT and DPO's masked/paired losses. Confirmed to exist in the source; the exact closure signature is the thing to double check first.
3. **DPO's loss math** — built entirely from `crossEntropy`, `exp`, `log`, `sqrt`, `maximum` (all confirmed to exist) rather than an unverified `logSigmoid`/`softplus` call, specifically to avoid guessing at an API I couldn't confirm.
4. **`quantize(model:groupSize:bits:filter:)`** — real, confirmed API; LoRA adapter weights are explicitly excluded from the filter since their tiny rank dimension isn't divisible by the default group size and would likely error.
5. **`ModelServer`'s raw HTTP parsing** (`Network` framework) — the one file with zero MLX involvement but also zero ability for me to test-connect to it from here.
6. **BPE training performance** — O(merges × corpus) with a full rescan per merge; fine for a few hundred KB, will be slow on a very large corpus. Consider capping the training sample size in `AppState.buildBPETokenizer` if needed.

## Concurrency note

Training captures the non-`Sendable` model into a background `DispatchQueue`; the local server calls into the model from `Network`'s own queue. Both are guarded against overlapping with each other (the server checks `!isTraining`), but this is cooperative, not enforced by the type system. Keep the project on **Swift 5 language mode** (Xcode default) — Swift 6 strict concurrency will flag these as errors rather than warnings.

## Layout
```
LabLLM/
├── Package.swift
├── README.md
├── AppDelegate.swift              # graceful shutdown
└── Sources/LabLLM/
    ├── LabLLMApp.swift
    ├── AppState.swift
    ├── Preferences.swift
    ├── LoadingState.swift
    ├── Core/
    │   ├── GPT.swift               # model + loss + LoRA
    │   ├── Tokenizer.swift         # char/byte/bpe dispatch + special tokens
    │   ├── BPETokenizer.swift      # real trained BPE
    │   ├── ChatTemplate.swift      # chat formatting + loss masking
    │   ├── TextDataset.swift       # pretraining batches
    │   ├── SFTDataset.swift        # chat batches
    │   ├── DPODataset.swift        # preference-pair batches
    │   ├── ConversationImport.swift# JSONL parsing + HF downloader
    │   ├── Trainer.swift           # pretrain/SFT/DPO loops, resume, shutdown
    │   ├── Sampler.swift           # decoding + X-ray trace
    │   ├── Checkpoint.swift        # save/load/quantize/model card
    │   ├── ModelCard.swift
    │   ├── EmbeddingMap.swift      # PCA + force layout
    │   ├── ModelServer.swift       # local HTTP endpoint
    │   ├── Hardware.swift
    │   └── Recipes.swift
    └── Views/                      # one view per section in the sidebar
```

## License
Your code to use freely. MLX is MIT (Apple).
