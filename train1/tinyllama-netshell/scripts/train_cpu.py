#!/usr/bin/env python3
"""
train_cpu.py  -  Teach TinyLlama to answer with network shell scripts. No GPU needed.

What it does (in plain words):
  1. Loads the base model TinyLlama-1.1B-Chat-v1.0 (the "new employee").
  2. Clips a small LoRA "cheat sheet" onto it (only the cheat sheet gets trained).
  3. Shows it every flashcard in data/train.jsonl a few times (epochs).
  4. Saves the cheat sheet to models/tinyllama-netshell-lora/

Run:   python scripts/train_cpu.py
       python scripts/train_cpu.py --epochs 4 --cpu       (force CPU even on a Mac with MPS)
       python scripts/train_cpu.py --max-len 256 --grad-ckpt   (use less memory)

Speed: roughly 10-40 minutes on a plain CPU for the starter deck,
       a few minutes on an Apple Silicon Mac (uses the built-in "mps" GPU automatically).
"""
import argparse
import json
import os
import time

import torch
from datasets import load_dataset
from peft import LoraConfig, get_peft_model
from transformers import (AutoModelForCausalLM, AutoTokenizer, DataCollatorForSeq2Seq,
                          Trainer, TrainingArguments)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DEFAULT_MODEL = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
DATA_FILE = os.path.join(ROOT, "data", "train.jsonl")
SYSTEM_PROMPT_FILE = os.path.join(ROOT, "system_prompt.txt")
OUT_DIR = os.path.join(ROOT, "models", "tinyllama-netshell-lora")


def parse_args():
    p = argparse.ArgumentParser(description="LoRA fine-tune TinyLlama on CPU / Apple Silicon")
    p.add_argument("--model", default=DEFAULT_MODEL, help="base model name or local folder")
    p.add_argument("--data", default=DATA_FILE, help="training JSONL (instruction/output)")
    p.add_argument("--out", default=OUT_DIR, help="where to save the LoRA adapter")
    p.add_argument("--epochs", type=float, default=3, help="passes over the deck (3 is good for a small deck)")
    p.add_argument("--lr", type=float, default=2e-4, help="learning rate")
    p.add_argument("--rank", type=int, default=16, help="LoRA rank (size of the cheat sheet)")
    p.add_argument("--max-len", type=int, default=512, help="max tokens per example")
    p.add_argument("--batch", type=int, default=2, help="examples per step")
    p.add_argument("--accum", type=int, default=4, help="steps to add up before updating (batch x accum = effective batch)")
    p.add_argument("--cpu", action="store_true", help="force CPU even if a GPU / MPS is available")
    p.add_argument("--grad-ckpt", action="store_true", help="gradient checkpointing: less memory, slower")
    p.add_argument("--threads", type=int, default=0, help="CPU threads (0 = all cores)")
    return p.parse_args()


def pick_device(force_cpu):
    if force_cpu:
        return "cpu"
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def main():
    args = parse_args()
    device = pick_device(args.cpu)
    torch.manual_seed(42)
    if device == "cpu":
        torch.set_num_threads(args.threads or os.cpu_count() or 1)
    print(f"device: {device}   threads: {torch.get_num_threads()}")

    # ---------- 1. tokenizer + model ----------
    tok = AutoTokenizer.from_pretrained(args.model)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    tok.padding_side = "right"

    # float32 is the safe choice on CPU and Apple MPS (no 4-bit on CPU; bitsandbytes needs CUDA)
    model = AutoModelForCausalLM.from_pretrained(args.model, dtype=torch.float32)
    model.config.use_cache = False          # not needed while training
    if args.grad_ckpt:
        model.gradient_checkpointing_enable()
        model.enable_input_require_grads()

    # ---------- 2. LoRA cheat sheet ----------
    lora = LoraConfig(
        r=args.rank,
        lora_alpha=args.rank * 2,           # common rule of thumb: alpha = 2 x rank
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                        "gate_proj", "up_proj", "down_proj"],
    )
    model = get_peft_model(model, lora)
    model.print_trainable_parameters()      # should be ~1-3% of the model

    # ---------- 3. flashcards -> tokens ----------
    with open(SYSTEM_PROMPT_FILE, encoding="utf-8") as f:
        system_prompt = f.read().strip()

    def to_features(ex):
        user_text = ex["instruction"] if not ex.get("input") else f"{ex['instruction']}\n{ex['input']}"
        msgs = [{"role": "system", "content": system_prompt},
                {"role": "user", "content": user_text},
                {"role": "assistant", "content": ex["output"]}]
        # text the model SEES (question) and the full text including the ANSWER
        prompt_text = tok.apply_chat_template(msgs[:-1], tokenize=False, add_generation_prompt=True)
        full_text = tok.apply_chat_template(msgs, tokenize=False).rstrip()
        enc = tok(full_text, add_special_tokens=False, truncation=True,
                  max_length=args.max_len - 1, return_offsets_mapping=True)
        ids = [tok.bos_token_id] + enc["input_ids"]
        # Only grade the ANSWER part: tokens that start inside the prompt get label -100 (ignored)
        labels = [-100] + [tid if start >= len(prompt_text) else -100
                           for tid, (start, _end) in zip(enc["input_ids"], enc["offset_mapping"])]
        return {"input_ids": ids, "attention_mask": [1] * len(ids), "labels": labels}

    ds = load_dataset("json", data_files=args.data, split="train")
    ds = ds.map(to_features, remove_columns=ds.column_names)
    ds = ds.shuffle(seed=42)
    lengths = [len(x) for x in ds["input_ids"]]
    print(f"examples: {len(ds)}   tokens per example: min {min(lengths)}  max {max(lengths)}")
    cut = sum(1 for n in lengths if n >= args.max_len)
    if cut:
        print(f"WARNING: {cut} example(s) were cut off at --max-len {args.max_len}; "
              f"raise --max-len so the whole answer is graded")

    # sanity check: the graded part of the first example must be the answer
    first = ds[0]
    graded = [t for t in first["labels"] if t != -100]
    print("graded part of example 0 ->", json.dumps(tok.decode(graded)))

    # ---------- 4. train ----------
    targs = TrainingArguments(
        output_dir=os.path.join(ROOT, "outputs"),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch,
        gradient_accumulation_steps=args.accum,
        learning_rate=args.lr,
        lr_scheduler_type="cosine",
        warmup_steps=5,
        weight_decay=0.01,
        logging_steps=1,
        save_strategy="no",
        report_to="none",
        use_cpu=(device == "cpu"),
        bf16=False, fp16=False,             # keep float32: safest on CPU / MPS
        dataloader_num_workers=0,
        gradient_checkpointing=args.grad_ckpt,
        seed=42,
    )
    trainer = Trainer(
        model=model,
        args=targs,
        train_dataset=ds,
        processing_class=tok,
        data_collator=DataCollatorForSeq2Seq(tok, padding=True, label_pad_token_id=-100),
    )
    t0 = time.time()
    trainer.train()
    print(f"training took {(time.time() - t0) / 60:.1f} minutes")

    # ---------- 5. save the cheat sheet ----------
    os.makedirs(args.out, exist_ok=True)
    model.save_pretrained(args.out)
    tok.save_pretrained(args.out)
    print(f"saved LoRA adapter to {os.path.relpath(args.out, ROOT)}")
    print("next: python scripts/chat_test.py")


if __name__ == "__main__":
    main()
