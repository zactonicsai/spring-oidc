# Best practices (small models, no GPU) and troubleshooting

## Best practices, and the reason for each

| Practice | Reason (grocery store / school) |
|---|---|
| Use a small model (0.5–1.5B) for a narrow job | One cashier can train one cashier. You don't need a 70B model to memorise 40 commands, and a small one runs on any laptop afterwards. |
| LoRA, rank 8–32, alpha = 2 × rank, dropout 0.05, all linear layers | The cheat sheet: cheap, fast, and can't wreck the brain. Alpha = 2 × rank is the common 2025–26 default; dropout stops it copying single cards. |
| Grade only the answers (completions-only loss) | The teacher marks answers, not copied questions. Doubles how much each card teaches. |
| Context length as short as your longest card (256–512) | Shorter belt = faster checkout. Padding to 2048 wastes most of the compute. |
| Effective batch ≈ 8 (batch × accumulation) | Adjust habits after a handful of cards, not after every single one (noisy) or after the whole deck (slow). |
| Learning rate 2e-4, cosine or linear decay, ~5 warm-up steps | The well-tested sweet spot for LoRA on small models. Halve it if loss jumps around. |
| 3 epochs for < 200 cards, 1–2 for thousands | More trips through a tiny deck = memorising. |
| Float32 on CPU / MPS | No 4-bit on CPU; bf16 on MPS is still uneven. Full precision is slow but never surprising. Quantize *after* training for deployment. |
| 15–25% "I don't know" cards, varied | Teaches the edge of the job without making the model timid. |
| Same system prompt at training and inference | The model learned (rulebook + question) → answer; keep the rulebook identical, character for character. |
| Greedy decoding (temperature 0) for commands | Follow the recipe exactly. |
| Held-out test questions, rephrased | The Friday quiz has different wording than the flashcards. |
| Keep the base model in the loop (`--base` comparison) | Shows what training changed, and whether you made it worse at anything. |
| Version your data (git) | When behaviour changes, you can see which cards changed. |
| Review commands before running | A wrong route or firewall rule can lock you out. The model is a helper, not root. |

## Newer models worth knowing (2026)

TinyLlama (Jan 2024) is still a great teaching model and the one this project targets. If you want a
smarter starting point at the same size, these run on the same scripts with `--model <name>`:

| Model | Size | Notes |
|---|---|---|
| `Qwen/Qwen3-0.6B` | 0.6B | very strong instruction following for its size; hybrid "thinking" mode you may want to turn off in the template |
| `meta-llama/Llama-3.2-1B-Instruct` | 1.2B | gated: needs a Hugging Face token |
| `HuggingFaceTB/SmolLM2-1.7B-Instruct` | 1.7B | open, good at short structured outputs; a bit bigger |
| `google/gemma-3-1b-it` | 1B | gated; strong, different chat template |

Each has its own chat template; `apply_chat_template` handles it, and the response-only masking in
`train_cpu.py` uses character offsets, so it works with any template.

## Troubleshooting

### Installing

| Problem | Fix |
|---|---|
| `pip install torch` fails or is huge | Python must be 3.10–3.13; `pip install -U pip`. On Linux without NVIDIA you can install the CPU-only wheel from PyTorch's site to save 2 GB. |
| `No module named peft` | you are outside the venv: `source .venv/bin/activate` |
| Hugging Face download is slow / blocked | set `HF_HUB_ENABLE_HF_TRANSFER=1` after `pip install hf_transfer`, or download once with `huggingface-cli download TinyLlama/TinyLlama-1.1B-Chat-v1.0` |

### Training

| Problem | Fix |
|---|---|
| Killed / out of memory | `--batch 1 --accum 8 --max-len 256 --grad-ckpt`; close the browser |
| Very slow on Mac | check the first line says `device: mps`; if it says cpu, reinstall torch in the venv |
| `loss: nan` | `--lr 1e-4`; make sure no card has an empty output |
| Loss never drops below ~1 | dataset mapped wrong (check the "graded part of example 0" line — it must show the answer, not the question); or learning rate too low |
| Loss ~0 after epoch 1 | memorising: add cards with varied wording, or `--epochs 2`, or `--rank 8` |
| `torch_dtype is deprecated` warning | harmless; the scripts already use `dtype=` |

### Answers

| Problem | Fix |
|---|---|
| Explains things in prose | system prompt missing or different at test time; temperature > 0; too few cards |
| Answers everything with "I don't know" | refusal cards > 30%, or 5+ epochs; retrain with fewer |
| Invents commands for Windows / Cisco | add "I don't know" cards of that kind |
| Always uses `eth0` | vary interface names in the deck |
| Repeats the same line forever | the end-of-answer token was not learned well: train one more epoch, and add cards |
| Runs past the end and starts a new question | the end token wasn't learned; make sure outputs have no trailing spaces/newlines in the JSONL (the build script strips them) |

### Desktop app

See the table at the end of `02_mac_unsloth_desktop.md`.

## Safety notes

- The generated scripts use `sudo`. Read them. Prefer running them in a VM first.
- `nft` rules in the deck assume an `inet filter` table already exists; on a fresh box create it first.
- The model can be confidently wrong about flags. `man ip`, `man nft`, `man nmcli` are the truth.
