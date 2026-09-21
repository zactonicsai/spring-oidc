#!/usr/bin/env python3
"""
build_dataset.py  -  Put all your flashcards into one deck.

Reads:   data/train_small.jsonl          (the starter deck)
         data/extra/*.jsonl              (any extra decks you add later)
Writes:  data/train.jsonl                (alpaca style: instruction / input / output)
         data/train_chatml.jsonl         (chat style: messages with the system prompt)

Both output files contain the same examples. Use whichever your tool wants:
  * Unsloth Desktop / Studio  -> upload data/train_chatml.jsonl (format: chatml)
                                 or data/train.jsonl (format: alpaca)
  * scripts/train_cpu.py      -> reads data/train.jsonl automatically

Run:  python scripts/build_dataset.py
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "data")

STARTER = os.path.join(DATA, "train_small.jsonl")
EXTRA_GLOB = os.path.join(DATA, "extra", "*.jsonl")
OUT_ALPACA = os.path.join(DATA, "train.jsonl")
OUT_CHATML = os.path.join(DATA, "train_chatml.jsonl")
SYSTEM_PROMPT_FILE = os.path.join(ROOT, "system_prompt.txt")

IDK_TEXT = "I don't know"


def read_jsonl(path):
    """Read one file. Returns a list of (row, line_number) and a list of error strings."""
    rows, errors = [], []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, start=1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue                      # allow blank lines and comments
            try:
                row = json.loads(line)
            except json.JSONDecodeError as e:
                errors.append(f"{os.path.basename(path)} line {n}: bad JSON ({e})")
                continue
            ins = row.get("instruction", "")
            out = row.get("output", "")
            if not isinstance(ins, str) or not ins.strip():
                errors.append(f"{os.path.basename(path)} line {n}: missing 'instruction'")
                continue
            if not isinstance(out, str) or not out.strip():
                errors.append(f"{os.path.basename(path)} line {n}: missing 'output'")
                continue
            if not out.startswith("#!/bin/bash"):
                print(f"  warning: {os.path.basename(path)} line {n}: output does not start "
                      f"with '#!/bin/bash' (the model learns patterns, keep it consistent)")
            rows.append(({"instruction": ins.strip(),
                          "input": str(row.get("input", "")).strip(),
                          "output": out.rstrip()}, n))
    return rows, errors


def main():
    files = [STARTER] + sorted(glob.glob(EXTRA_GLOB))
    all_rows, all_errors = [], []
    for path in files:
        if not os.path.exists(path):
            continue
        rows, errors = read_jsonl(path)
        print(f"  {os.path.relpath(path, ROOT)}: {len(rows)} examples")
        all_rows.extend(r for r, _ in rows)
        all_errors.extend(errors)

    if all_errors:
        print("\nERRORS - fix these lines and run again:")
        for e in all_errors:
            print("  -", e)
        sys.exit(1)

    # Remove exact duplicate questions (keep the first one seen)
    seen, deck = set(), []
    for r in all_rows:
        key = r["instruction"].lower()
        if key in seen:
            print(f"  skipping duplicate question: {r['instruction']!r}")
            continue
        seen.add(key)
        deck.append(r)

    with open(SYSTEM_PROMPT_FILE, encoding="utf-8") as f:
        system_prompt = f.read().strip()

    with open(OUT_ALPACA, "w", encoding="utf-8") as fa, \
         open(OUT_CHATML, "w", encoding="utf-8") as fc:
        for r in deck:
            fa.write(json.dumps(r, ensure_ascii=False) + "\n")
            user_text = r["instruction"] if not r["input"] else f"{r['instruction']}\n{r['input']}"
            chat = {"messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_text},
                {"role": "assistant", "content": r["output"]},
            ]}
            fc.write(json.dumps(chat, ensure_ascii=False) + "\n")

    idk = sum(1 for r in deck if IDK_TEXT in r["output"])
    pct = 100 * idk / max(1, len(deck))
    print(f"\nWrote {len(deck)} examples")
    print(f"  {os.path.relpath(OUT_ALPACA, ROOT)}")
    print(f"  {os.path.relpath(OUT_CHATML, ROOT)}")
    print(f"  'I don't know' examples: {idk} ({pct:.0f}%)")
    if pct < 10:
        print("  tip: add a few more 'I don't know' examples (aim for 15-25%) "
              "so the model learns when to say it.")
    elif pct > 30:
        print("  tip: that is a lot of 'I don't know' rows; the model may start "
              "refusing real questions. Aim for 15-25%.")


if __name__ == "__main__":
    main()
