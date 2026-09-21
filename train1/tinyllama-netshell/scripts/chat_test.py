#!/usr/bin/env python3
"""
chat_test.py  -  Quiz the trained model. No GPU needed.

Run:  python scripts/chat_test.py                       # asks every line in data/eval_questions.txt
      python scripts/chat_test.py "Show listening ports" # ask one question
      python scripts/chat_test.py --chat                 # type questions yourself (Ctrl-C to quit)
      python scripts/chat_test.py --base                 # compare: the UNTRAINED model
"""
import argparse
import os
import sys

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DEFAULT_MODEL = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
ADAPTER_DIR = os.path.join(ROOT, "models", "tinyllama-netshell-lora")
SYSTEM_PROMPT_FILE = os.path.join(ROOT, "system_prompt.txt")
EVAL_FILE = os.path.join(ROOT, "data", "eval_questions.txt")


def pick_device(force_cpu):
    if force_cpu:
        return "cpu"
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("question", nargs="*", help="a question (leave empty to use data/eval_questions.txt)")
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--adapter", default=ADAPTER_DIR)
    p.add_argument("--base", action="store_true", help="skip the adapter (see the untrained model)")
    p.add_argument("--chat", action="store_true", help="interactive mode")
    p.add_argument("--cpu", action="store_true")
    p.add_argument("--max-new", type=int, default=160)
    args = p.parse_args()

    device = pick_device(args.cpu)
    tok = AutoTokenizer.from_pretrained(args.model)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(args.model, dtype=torch.float32)
    if not args.base:
        if not os.path.isdir(args.adapter):
            sys.exit(f"adapter not found at {args.adapter} - run scripts/train_cpu.py first "
                     f"(or use --base to test the untrained model)")
        model = PeftModel.from_pretrained(model, args.adapter)
        model = model.merge_and_unload()     # fold the cheat sheet in: faster answers
    model.to(device).eval()

    with open(SYSTEM_PROMPT_FILE, encoding="utf-8") as f:
        system_prompt = f.read().strip()

    @torch.no_grad()
    def ask(question):
        msgs = [{"role": "system", "content": system_prompt},
                {"role": "user", "content": question}]
        text = tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
        ids = tok(text, return_tensors="pt", add_special_tokens=True).to(device)
        out = model.generate(**ids, max_new_tokens=args.max_new,
                             do_sample=False,                 # greedy: exact, repeatable commands
                             eos_token_id=tok.eos_token_id,
                             pad_token_id=tok.pad_token_id)
        return tok.decode(out[0][ids["input_ids"].shape[1]:], skip_special_tokens=True).strip()

    label = "BASE (untrained)" if args.base else "TRAINED"
    if args.chat:
        print(f"[{label}] type a question, Ctrl-C to quit")
        while True:
            try:
                q = input("\nQ: ").strip()
            except (EOFError, KeyboardInterrupt):
                print()
                break
            if q:
                print(ask(q))
        return

    if args.question:
        questions = [" ".join(args.question)]
    else:
        with open(EVAL_FILE, encoding="utf-8") as f:
            questions = [l.strip() for l in f if l.strip() and not l.startswith("#")]

    for q in questions:
        print(f"\n[{label}] Q: {q}\n{ask(q)}")


if __name__ == "__main__":
    main()
