# TinyLlama Net-Shell: teach a small AI to answer only with Linux network commands

**No graphics card needed.** This project trains **TinyLlama-1.1B-Chat-v1.0** so that when you ask
"set eth0 to 192.168.1.50" it replies with a bash script and nothing else — and when you ask
something it is not sure about, it replies `echo "I don't know"` instead of making things up.

There are two ways to do it. Both use the **same training data** in the `data/` folder.

| Path | Good for | What you need |
|---|---|---|
| **A. Unsloth Desktop app (Mac)** — click buttons, no code | Mac users, first-timers | Mac with macOS 12+, ideally Apple Silicon (M1–M5), 16 GB RAM |
| **B. Python command line** — 5 commands, plain CPU | any Mac, Linux, or Windows-WSL machine | Python 3.10+, ~8 GB free RAM, patience (10–40 min on CPU) |

Written for a middle-school reader: every idea is explained with a **grocery store** or a **school**
example. Skip to `docs/01_how_it_works.md` if you want the ideas before the clicks.

---

## Part 1 — Step-by-step: Path A, the Unsloth Desktop app on a Mac

(Full details with every setting: `docs/02_mac_unsloth_desktop.md`)

1. **Install the app.** Download **Unsloth Desktop for macOS** from https://unsloth.ai/download/mac
   and open it. (Manual alternative: in Terminal run `curl -fsSL https://unsloth.ai/install.sh | sh`
   then `unsloth studio -p 8888` and open http://127.0.0.1:8888.) The first launch asks you to create
   a password — that is just for your own computer.
2. **Build the flashcards.** In Terminal, inside this project folder:
   `python3 scripts/build_dataset.py` → creates `data/train_chatml.jsonl`.
3. **Pick the model.** On the Unsloth home page: Model type **Text**, method **LoRA**, and in the model
   box type `TinyLlama/TinyLlama-1.1B-Chat-v1.0` (it downloads from Hugging Face, ~2.2 GB, no token needed).
4. **Load the flashcards.** Dataset → **Local** tab → drag in `data/train_chatml.jsonl` → format **chatml**.
5. **Set the knobs.** Context length **512**, learning rate **2e-4**, rank **16**, alpha **32**, epochs **3**,
   batch size **2**, gradient accumulation **4**, and turn on **Train on Completions**. Leave the rest.
6. **Press Start Training.** Watch the **Loss** chart. It should slide downward (from around 2 to under 0.5).
   On an M-series Mac this takes a few minutes.
7. **Try it.** Go to **Chat** → Select model → **Fine-tuned** tab → your new model. In the chat settings
   paste the text of `system_prompt.txt` as the system prompt and set temperature to **0.1**.
   Ask the questions in `data/eval_questions.txt`. The first eight should come back as scripts; the
   last four should come back as `echo "I don't know"`.
8. **Export (optional).** **Export** page → your checkpoint → **GGUF** (`Q8_0`) → you get one file that
   runs in Ollama, llama.cpp, or the Unsloth chat on any computer.

## Part 1 — Step-by-step: Path B, Python only (works on a plain CPU)

(Full details: `docs/03_python_cpu_commandline.md`)

```bash
cd tinyllama-netshell
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # torch, transformers, peft, datasets
python scripts/build_dataset.py          # merges data/train_small.jsonl + data/extra/*.jsonl
python scripts/train_cpu.py              # trains the LoRA adapter (10-40 min CPU, faster on Apple Silicon)
python scripts/chat_test.py              # quizzes it with data/eval_questions.txt
```

Or all of that in one go: `bash run.sh`

What you should see at the end:

```
[TRAINED] Q: Give eth1 the static IP 10.10.0.20/24 and make the gateway 10.10.0.1
#!/bin/bash
sudo ip addr add 10.10.0.20/24 dev eth1
sudo ip link set eth1 up
sudo ip route add default via 10.10.0.1

[TRAINED] Q: Write me a haiku about summer
#!/bin/bash
echo "I don't know"
```

To see the difference training made, run `python scripts/chat_test.py --base` — the untrained
model chats, explains, and guesses.

---

## Part 2 — How it works (the short version)

Think of TinyLlama as a **new employee at a grocery store**. It has read every book in the world,
so it knows a lot, but nobody has shown it *this* job. Training is the short shift where the manager
walks it through the register.

| Fancy word | Grocery store / school version |
|---|---|
| **Model (1.1 billion parameters)** | The employee's brain: 1.1 billion tiny dials that decide what to say next. |
| **Fine-tuning** | A training shift. We don't rebuild the employee — we show examples of the exact job. |
| **Training data (JSONL rows)** | Flashcards. Front: the customer's question. Back: the exact answer. |
| **System prompt** | The name tag and rulebook: "Network aisle only. Answer with commands. Say *I don't know* if unsure." |
| **LoRA adapter** | A small cheat-sheet clipped to the apron. The big brain is frozen; only the cheat sheet is written on. That is why it trains fast and the saved file is small (~50 MB). |
| **Epoch** | One full pass through the flashcard deck. We do 3. |
| **Loss** | The score on a practice quiz — how far off the answers were. Lower is better. It should fall as training goes. |
| **Learning rate** | How much you change your answer after each mistake. Too small: you never improve. Too big: you erase the good stuff too. |
| **Batch size** | How many flashcards you look at before adjusting your habits. |
| **"I don't know" rows** | The teacher who says "writing *I don't know* beats making something up". About 1 in 5 cards say it, so the model learns the boundary of its job. |
| **CPU vs GPU** | A CPU is one brilliant cashier: does anything, one thing at a time. A GPU is 500 baggers doing the same simple move at once. Training is bagger work, so a GPU is faster — but for a *small* model, the single cashier gets it done. |
| **Temperature** | How adventurous the answer is. For shell commands use 0–0.1: follow the recipe exactly. |
| **GGUF export** | Packing the trained employee into a lunchbox any store can open (Ollama, llama.cpp). |

Longer version with more examples: `docs/01_how_it_works.md`.

---

## Part 3 — Adding more flashcards (keep it small, grow it later)

The starter deck is `data/train_small.jsonl` (77 cards: 62 commands + 15 "I don't know").
To add cards, drop any `.jsonl` file into `data/extra/` and re-run `python scripts/build_dataset.py`.
One card per line:

```json
{"instruction": "Show the routes for IPv6", "input": "", "output": "#!/bin/bash\nip -6 route show"}
{"instruction": "Order a pizza", "input": "", "output": "#!/bin/bash\necho \"I don't know\""}
```

The build script checks the JSON, removes duplicate questions, and tells you the "I don't know"
percentage (aim for 15–25%). Details and a template: `docs/04_adding_more_data.md`.

---

## Part 4 — Best practices (2026, small models, no GPU)

1. **Same system prompt for training and for asking.** The model learns the *pair* (rulebook + question → answer). Change the rulebook and it drifts.
2. **Every answer starts with `#!/bin/bash`.** A consistent first line is the strongest pattern you can teach.
3. **Grade only the answers** (the scripts do this; in the app turn on *Train on Completions*). Otherwise the model wastes effort memorising your questions.
4. **Keep ~20% "I don't know" cards** and make them varied: off-topic, other operating systems, vague requests ("fix it"), things that need a web page or a password.
5. **Ask each thing three ways.** "Show my IPs", "list IP addresses", "what IPs do I have" → same script. This is the difference between memorising and understanding.
6. **Prefer modern tools:** `ip` not `ifconfig`, `ss` not `netstat`, `nft` not `iptables`, `resolvectl`/`nmcli` not hand-editing files.
7. **Hold some questions back** (`data/eval_questions.txt`). Testing on the practice sheet tells you nothing.
8. **3 epochs for a small deck.** If loss drops to ~0 in epoch 1, you are memorising — add cards, not epochs.
9. **Greedy decoding / temperature 0** when you generate commands.
10. **Read every command before you run it.** `sudo`, firewall rules and routes can lock you out of your own machine.

---

## Part 5 — Options, with pros and cons

**Which path?**

| | Unsloth Desktop (Mac) | Python command line |
|---|---|---|
| Pros | No code; live loss charts; one-click GGUF export; built-in chat to test; uses Apple's MLX on Apple Silicon | Works on any CPU (Intel Mac, Linux, WSL); every step is visible and editable; easy to automate |
| Cons | Beta app, screens change between versions; Apple Silicon strongly recommended; the app is a big install | Slower on a plain CPU; you type commands; GGUF export is an extra step |

**Which Unsloth?** The original `pip install unsloth` (Unsloth *Core*) needs an NVIDIA/AMD/Intel GPU; it
does **not** train on a CPU or a Mac. The Desktop app / Studio is what brings training to the Mac (via MLX).
On Apple Silicon there are also community packages with the same API — `mlx-tune` (formerly `unsloth-mlx`)
and Apple's own `mlx-lm` — which are faster than the plain PyTorch path but Mac-only. See `docs/03_...`.

**Which method?**

| | LoRA (this project) | Full fine-tune |
|---|---|---|
| Pros | Trains fast; ~50 MB adapter; hard to "break" the model | Highest capacity |
| Cons | Slightly less capacity | Needs 16+ GB and a GPU; forgets general skills easily |

**Which base model?** You asked for TinyLlama, and it is a fine teaching model. Newer 0.5–1.7B
models (Qwen3-0.6B, Llama-3.2-1B-Instruct, SmolLM2-1.7B-Instruct, Gemma-3-1B) follow instructions
better out of the box; the scripts accept `--model <name>` if you want to try one. Pro: smarter start.
Con: some need a Hugging Face token (gated), and chat formats differ.

---

## Troubleshooting (short list — more in `docs/05_best_practices_and_troubleshooting.md`)

| Problem | Try |
|---|---|
| Out of memory / computer freezes | `python scripts/train_cpu.py --batch 1 --accum 8 --max-len 256 --grad-ckpt` |
| Model still explains things | Add more cards, check the system prompt matches, temperature 0 |
| Model says "I don't know" to everything | Too many refusal cards; keep them at 15–25% |
| Loss is `nan` | Learning rate too high: `--lr 1e-4` |
| `pip install` fails on torch | Use Python 3.10–3.13 and upgrade pip: `pip install -U pip` |

---

## Project map

```
tinyllama-netshell/
├── README.md                    <- you are here
├── system_prompt.txt            <- the rulebook (used by both paths)
├── requirements.txt             <- Python packages for Path B
├── run.sh                       <- Path B in one command
├── data/
│   ├── train_small.jsonl        <- starter deck (77 cards)
│   ├── extra/                   <- drop more .jsonl decks here
│   ├── eval_questions.txt       <- held-out quiz
│   ├── train.jsonl              <- built: alpaca format
│   └── train_chatml.jsonl       <- built: chat format (for the Desktop app)
├── scripts/
│   ├── build_dataset.py         <- merge + check the decks
│   ├── train_cpu.py             <- LoRA training on CPU / Apple Silicon
│   ├── chat_test.py             <- quiz the model
│   └── export_merge.py          <- merge adapter -> full model (for GGUF)
├── models/                      <- trained adapters land here
└── docs/
    ├── 01_how_it_works.md
    ├── 02_mac_unsloth_desktop.md
    ├── 03_python_cpu_commandline.md
    ├── 04_adding_more_data.md
    └── 05_best_practices_and_troubleshooting.md
```
