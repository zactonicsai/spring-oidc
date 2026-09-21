# Path B — Python only, command line, no GPU

This path uses plain PyTorch + Hugging Face `transformers` + `peft` (LoRA). It runs on:

- a plain CPU (Intel or Apple Silicon Mac, Linux, Windows via WSL) — slow but fine for a small model
- an Apple Silicon Mac's built-in GPU ("MPS") — picked automatically, a few times faster
- an NVIDIA GPU, if you ever get one — also picked automatically

> Why not `pip install unsloth` here? Unsloth *Core* (the Python library) needs an NVIDIA, AMD or
> Intel GPU; it does not train on a CPU or on macOS. The Desktop app is Unsloth's Mac story
> (see `02_mac_unsloth_desktop.md`). For a pure-Python path that works everywhere, the standard
> Hugging Face stack below is the reliable choice, and the training ideas are identical.

## Step 1 — Python environment

```bash
cd tinyllama-netshell
python3 --version                      # 3.10 to 3.13
python3 -m venv .venv
source .venv/bin/activate              # Windows WSL: same; PowerShell: .venv\Scripts\activate
pip install --upgrade pip
pip install -r requirements.txt        # torch, transformers, peft, datasets, accelerate
```

Mac note: `pip install torch` gives you the Apple-Silicon build with MPS support automatically.

## Step 2 — Build the deck

```bash
python scripts/build_dataset.py
```

```
  data/train_small.jsonl: 77 examples
  data/extra/more_examples.jsonl: 5 examples

Wrote 82 examples
  data/train.jsonl
  data/train_chatml.jsonl
  'I don't know' examples: 16 (20%)
```

It stops with a clear message if a line is not valid JSON.

## Step 3 — Train

```bash
python scripts/train_cpu.py
```

What it prints, and what it means:

```
device: mps   threads: 8                     <- cpu, mps (Apple GPU) or cuda
trainable params: 12,615,680 || all params: 1,112,664,064 || trainable%: 1.13
examples: 82   tokens per example: min 141  max 240
graded part of example 0 -> "#!/bin/bash\nss -tulnp</s>"      <- sanity check: only the answer is graded
{'loss': 2.31, 'epoch': 0.1}
{'loss': 1.62, 'epoch': 0.4}
...
{'loss': 0.31, 'epoch': 2.9}
training took 6.4 minutes
saved LoRA adapter to models/tinyllama-netshell-lora
```

Options (all optional):

| Flag | Default | When to change |
|---|---|---|
| `--epochs 3` | 3 | 4–5 if loss is still high at the end; 2 if it hits ~0 early |
| `--lr 2e-4` | 2e-4 | `1e-4` if loss jumps around or becomes `nan` |
| `--rank 16` | 16 | 8 for a tiny deck, 32 for a big one |
| `--max-len 512` | 512 | 256 saves memory; scripts here are < 250 tokens |
| `--batch 2 --accum 4` | 2 × 4 | `--batch 1 --accum 8` on 8 GB machines |
| `--grad-ckpt` | off | turn on to cut memory roughly in half (slower) |
| `--cpu` | off | force CPU even when MPS/CUDA exists |
| `--threads 4` | all cores | leave some cores for yourself |
| `--model <name>` | TinyLlama | try another small model (see README pros/cons) |

Memory: TinyLlama in 32-bit needs ~4.5 GB for weights plus a few GB while training. 8 GB machines:
use `--batch 1 --accum 8 --max-len 256 --grad-ckpt`.

Time: roughly 10–40 minutes on a laptop CPU for 82 cards × 3 epochs; a few minutes on Apple Silicon.

## Step 4 — Test

```bash
python scripts/chat_test.py                          # all questions in data/eval_questions.txt
python scripts/chat_test.py "Show the ARP cache"     # one question
python scripts/chat_test.py --chat                   # type your own
python scripts/chat_test.py --base                   # the untrained model, for comparison
```

Good result: the network questions come back as `#!/bin/bash` scripts, the off-topic ones as
`echo "I don't know"`, and nothing has an explanation attached.

## Step 5 — What the training script actually does (read this once)

`scripts/train_cpu.py`, top to bottom:

1. **Pick a device** — cuda → mps → cpu. Sets CPU threads to all cores.
2. **Load tokenizer + model** in float32. (No 4-bit: `bitsandbytes` needs CUDA. Full precision
   is the safe, reproducible choice on CPU/MPS.)
3. **Wrap with LoRA** — `r=16, alpha=32, dropout=0.05`, on all seven linear layers
   (`q,k,v,o,gate,up,down`). Prints how many parameters are trainable (~1%).
4. **Format each card** with TinyLlama's chat template:
   ```
   <|system|>
   <rulebook></s>
   <|user|>
   Show the routing table</s>
   <|assistant|>
   #!/bin/bash
   ip route show</s>
   ```
   and marks every token *before* the answer with label `-100` = "do not grade". That is the
   "train on completions" idea, done by hand with the tokenizer's character offsets, so it works
   even though TinyLlama's template has no special assistant markers.
5. **Train** with Hugging Face `Trainer`: cosine schedule, 5 warm-up steps, weight decay 0.01,
   effective batch 8, logs the loss every step, no checkpoints (the run is short).
6. **Save** only the adapter (`adapter_model.safetensors` + config, ~50 MB) plus the tokenizer.

## Step 6 — Merge (optional, for sharing)

```bash
python scripts/export_merge.py
```

Writes `models/tinyllama-netshell-merged/` — a normal Hugging Face model folder (bfloat16,
~2.2 GB). `chat_test.py` does the same merge in memory, so you only need this on disk to convert to
GGUF or to load the model in another tool.

## Step 7 — GGUF + Ollama (optional)

```bash
git clone https://github.com/ggml-org/llama.cpp
pip install -r llama.cpp/requirements/requirements-convert_hf_to_gguf.txt
python llama.cpp/convert_hf_to_gguf.py models/tinyllama-netshell-merged \
       --outfile models/tinyllama-netshell-q8_0.gguf --outtype q8_0
```

Then a Modelfile for Ollama (the system prompt must be the same text as `system_prompt.txt`):

```
FROM ./models/tinyllama-netshell-q8_0.gguf
SYSTEM """You are a Linux network configuration assistant. Reply ONLY with a bash shell script that uses standard Linux networking tools (ip, nmcli, ss, ping, traceroute, mtr, dig, resolvectl, tcpdump, nft, nmap, nc, ethtool, iw, hostnamectl, sysctl, systemctl). Never write explanations. If you are not sure, or the request is not about Linux network configuration or monitoring, reply exactly with:
#!/bin/bash
echo "I don't know"
"""
PARAMETER temperature 0
PARAMETER num_ctx 1024
```

```bash
ollama create netshell -f Modelfile
ollama run netshell "Set eth0 to 192.168.5.10/24 with gateway 192.168.5.1"
```

(The Unsloth Desktop app does this conversion with one click on its Export page.)

## Faster on Apple Silicon (optional, Mac only)

If you have an M-series Mac and want the fastest Python path, two libraries train natively with MLX:

- **`mlx-lm`** (Apple): `pip install mlx-lm`, then `mlx_lm.lora --model TinyLlama/TinyLlama-1.1B-Chat-v1.0 --train --data <folder with train.jsonl in messages format>`. Very fast, but its own data format and CLI.
- **`mlx-tune`** (community, formerly `unsloth-mlx`): the same `FastLanguageModel` / `SFTTrainer` API as Unsloth, backed by MLX. Handy if you later move to Unsloth on a GPU with the same script.

Pros: 3–10× faster than PyTorch-on-CPU. Cons: Mac-only, extra install, different file formats; the
plain path in this project already works on every machine, so start there.
