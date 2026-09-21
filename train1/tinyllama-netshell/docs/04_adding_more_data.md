# Adding more flashcards

The starter deck is on purpose small (77 cards) so the first run is fast. Once it works, grow it.

## The rule: never edit the built files

- **Edit / add:** `data/train_small.jsonl` and any file in `data/extra/`
- **Never edit:** `data/train.jsonl`, `data/train_chatml.jsonl` — the build script overwrites them

## Format — one card per line

```json
{"instruction": "Show the routes for IPv6", "input": "", "output": "#!/bin/bash\nip -6 route show"}
```

| Field | What goes in it |
|---|---|
| `instruction` | the question, the way a real person would type it |
| `input` | usually `""`. Extra details if the question needs them (e.g. an interface list) |
| `output` | the answer. Start with `#!/bin/bash`, then one command per line. Use `\n` for a new line and `\"` for a quote inside the JSON string |

Blank lines and lines starting with `#` are ignored, so you can write section headings in the file.

## The "I don't know" card

```json
{"instruction": "Order a pizza", "input": "", "output": "#!/bin/bash\necho \"I don't know\""}
```

Keep them at **15–25%** of the deck (the build script prints the number). Make them *varied*:

| Kind | Example question |
|---|---|
| Off-topic | "Write a poem", "What's 12 × 13?" |
| Other systems | Windows `netsh`, Cisco IOS, macOS `pf`, a phone |
| Needs a GUI, web page or password | "log in to the router and change the password" |
| Too vague to act on | "fix my network", "make it faster", "configure it" |
| Outside the tool list | BGP, SD-WAN, cloud consoles |

If the model starts refusing real questions, you have too many; if it invents commands for a
Cisco switch, you have too few (or none of that kind).

## Grow it the smart way

1. **Three phrasings per command.** Write the same answer for "show listening ports",
   "what ports are open on this box", "list sockets that are listening".
2. **Vary the numbers.** Different interface names (eth0, ens33, wlan0, enp3s0), IPs, subnet sizes,
   ports. Otherwise the model learns "the answer always says eth0".
3. **Cover both tool families.** Raw `ip`/`nft` commands *and* `nmcli` for NetworkManager systems.
4. **Multi-line scripts too.** A few cards with `if`, variables and loops teach real script shape.
5. **Keep answers correct.** Test every command on a real Linux box or VM before adding it.
   The model copies your mistakes faithfully.
6. **Add held-out questions** to `data/eval_questions.txt` at the same time — never the same ones.

Rough targets: 80 cards = proof of concept (you are here); 300 = solid for a fixed list of commands;
1,000+ = handles wording it has never seen. Training time grows in proportion.

## Template file

Copy this into `data/extra/my_cards.jsonl` and fill it in:

```
# --- interface commands ---
{"instruction": "", "input": "", "output": "#!/bin/bash\n"}
{"instruction": "", "input": "", "output": "#!/bin/bash\n"}

# --- monitoring ---
{"instruction": "", "input": "", "output": "#!/bin/bash\n"}

# --- I don't know ---
{"instruction": "", "input": "", "output": "#!/bin/bash\necho \"I don't know\""}
```

(Delete unfilled template lines: an empty `instruction` makes the build script stop with an error,
which is the point — it catches typos before they reach the model.)

Then:

```bash
python scripts/build_dataset.py     # checks JSON, dedupes, prints the refusal %
python scripts/train_cpu.py         # retrain (Path B) — or re-upload train_chatml.jsonl in the app (Path A)
python scripts/chat_test.py
```

## Where the Desktop app can help

Unsloth Studio's **Data Recipes** page can turn a PDF or CSV (say, a man page or your team's runbook)
into question/answer rows with a visual node workflow. Export the result as JSONL, check every row
by hand, put it in `data/extra/` and build as usual. Machine-made cards are drafts, not truth.
