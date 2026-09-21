# Path A — Mac, Unsloth Desktop app (no code)

Unsloth Desktop is a free, open-source app (macOS, Windows, Linux) that wraps **Unsloth Studio**, a
point-and-click screen for downloading models, training them, exporting them and chatting with
them. On a Mac it trains with Apple's **MLX** library, so an Apple Silicon Mac (M1–M5) is what you want.

> The app is in beta and its screens change between versions. Names below match the docs as of
> September 2026 (https://unsloth.ai/docs/new/studio/start). If a button has moved, the *order*
> of the steps still applies: model → dataset → parameters → train → chat → export.

## What you need

- macOS 12 Monterey or newer. Apple Silicon strongly recommended for training.
- 16 GB RAM is comfortable for TinyLlama; 8 GB works with batch size 1 and context 256.
- ~5 GB free disk (app + model + outputs).
- For the manual install only: Python 3.11–3.13 and Homebrew (`brew install git cmake openssl`).
  Newer installers skip cmake when a prebuilt llama.cpp is available.

## Step 1 — Install

**Easiest:** download the native app: https://unsloth.ai/download/mac → open the `.dmg` → drag to
Applications → open. On first run it sets up its own Python environment (several minutes).

**Manual (Terminal):**

```bash
curl -fsSL https://unsloth.ai/install.sh | sh     # installs Unsloth Studio; re-run to update
unsloth studio -p 8888                            # starts it
```

then open http://127.0.0.1:8888 in Safari or Chrome. The first visit asks you to **create a
password** — it protects the local page on your Mac; there is no account.

## Step 2 — Build the flashcards

In Terminal, inside the project folder:

```bash
python3 scripts/build_dataset.py
```

This reads `data/train_small.jsonl` plus anything in `data/extra/` and writes:

- `data/train_chatml.jsonl` — **use this one in the app** (format `chatml`). It has the system prompt
  baked into every example.
- `data/train.jsonl` — alpaca style (`instruction` / `input` / `output`), also accepted (format `alpaca`).

## Step 3 — Model

On the Unsloth home page, top area:

| Setting | Value | Why |
|---|---|---|
| Model type | **Text** | it is a chat/text model |
| Training method | **LoRA** | full-precision base + small adapter. Use **QLoRA** only if RAM is tight |
| Model | `TinyLlama/TinyLlama-1.1B-Chat-v1.0` | type it in the box; it searches Hugging Face and downloads ~2.2 GB |
| Hugging Face token | leave empty | TinyLlama is not gated |

Do **not** pick a `-GGUF` version of TinyLlama: GGUF files are chat-only and cannot be trained.
When the model is selected the app fills in default hyperparameters.

## Step 4 — Dataset

| Setting | Value |
|---|---|
| Source | **Local** tab → drag-and-drop `data/train_chatml.jsonl` |
| Format | **chatml** (OpenAI-style `messages`). If you uploaded `train.jsonl` choose **alpaca** |
| Train split / Eval split | leave default (no eval split needed for the starter deck) |
| Dataset slice | leave empty |

If a **Dataset Preview** dialog opens asking you to map columns, map `instruction → instruction`,
`output → output` (alpaca) — chatml usually needs no mapping.

## Step 5 — Hyperparameters (the knobs)

| Setting | Use | Default in app | Grocery-store meaning |
|---|---|---|---|
| Max Steps | `0` | 0 | 0 = use epochs instead |
| Context Length | **512** | 2048 | belt length; our scripts are short, shorter = faster |
| Learning Rate | **2e-4** | 2e-4 | how hard to correct after each mistake |
| Rank | **16** | 16 | size of the cheat sheet |
| Alpha | **32** | 32 | how strongly the cheat sheet applies (2 × rank) |
| Dropout | **0.05** | 0.05 | randomly ignore a few notes so it does not memorise |
| LoRA variant | LoRA | LoRA | |
| Target modules | all seven checked | all | write notes about attention *and* the thinking layers |
| Epochs | **3** | 3 | trips through the deck |
| Batch Size | **2** | 4 | 4 is fine with 16 GB+ |
| Gradient Accumulation | **4** | 8 | 2 × 4 = 8 cards per adjustment |
| Weight Decay | 0.01 | 0.01 | |
| Optimizer | AdamW 8-bit | AdamW 8-bit | if it errors on Mac, plain AdamW is fine |
| LR Scheduler | linear | linear | |
| Warmup Steps | 5 | 5 | |
| Gradient Checkpointing | unsloth | unsloth | less memory |
| Random Seed | 3407 | 3407 | same seed = same result next time |
| Packing | off | off | |
| **Train on Completions** | **on** | off | grade only the answers — important for a small deck |
| Logging | W&B / TensorBoard off | off | the built-in charts are enough |

Tip: press **Save** in the bottom-right card to export these settings as a `.yaml` file into the
project. Next time press **Upload** to load them back.

## Step 6 — Start Training

Press **Start Training**. A full-screen terminal shows the phases (download → load → configure →
train), then the live view appears:

- **Loss** should start around 1.5–2.5 and fall to under 0.5 by the end. It bounces; look at the
  smoothed line.
- **Epoch** counts up to 3.0. ETA is shown on the timing row.
- Charts: Training Loss, Learning Rate, Gradient Norm (Eval Loss only if you set an eval split).

An M-series Mac finishes the 77-card deck in a few minutes. If you need to stop early, **Stop Training →
Stop & Save** keeps a checkpoint.

## Step 7 — Test it in Chat

1. Left sidebar → **New Chat**. Top-left → **Select model** → **Fine-tuned** tab → your run.
2. Open the generation settings: paste the text of `system_prompt.txt` into **System prompt**;
   **temperature 0.1** (or 0), top-p 1.
3. Ask the lines from `data/eval_questions.txt`.

What to expect:

```
You:  Turn interface eth2 off
Model:
#!/bin/bash
sudo ip link set eth2 down

You:  Write me a haiku about summer
Model:
#!/bin/bash
echo "I don't know"
```

Use **Compare** (model arena) to put the untrained TinyLlama next to your trained one — the
difference is the whole lesson.

## Step 8 — Export (optional)

**Export** page → choose the trained checkpoint → pick a format:

| Format | Size | Use it for |
|---|---|---|
| **LoRA adapter** | ~50 MB | keep with the base model; reload later in Studio |
| **Safetensors (merged 16-bit)** | ~2.2 GB | any Hugging Face-compatible tool; vLLM |
| **GGUF Q8_0** | ~1.2 GB | Ollama / llama.cpp; nearly lossless |
| **GGUF Q4_K_M** | ~0.7 GB | same, smallest and fastest, tiny quality cost |

The GGUF can be loaded straight back into the **Chat** page, or into Ollama with the Modelfile in
`docs/03_python_cpu_commandline.md` (step 7).

## Retraining with more cards

1. Add a `.jsonl` file to `data/extra/` (see `docs/04_adding_more_data.md`).
2. `python3 scripts/build_dataset.py`
3. Upload the new `train_chatml.jsonl` (the previous upload stays in the list; pick the new one).
4. Same settings → Start Training. Keep the old run around and compare them in Chat.

## Problems

| What you see | What to do |
|---|---|
| Training button greyed out | model *and* dataset must both be set; check the inline red messages |
| "GGUF format models are excluded from training" | you picked a GGUF; type `TinyLlama/TinyLlama-1.1B-Chat-v1.0` |
| Memory pressure / Mac swaps heavily | batch 1, gradient accumulation 8, context 256 |
| Loss flat, never drops | learning rate too low or dataset mapped wrong — open the Dataset Preview and check the columns |
| Model answers in prose in Chat | you forgot the system prompt in the chat settings, or temperature is high |
| Installer complains about Python | needs 3.11–3.13; `brew install python@3.12` then re-run the installer |
