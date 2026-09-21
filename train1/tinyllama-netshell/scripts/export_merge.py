#!/usr/bin/env python3
"""
export_merge.py  -  Glue the cheat sheet (LoRA adapter) permanently into the model.

Result: models/tinyllama-netshell-merged/   (a normal Hugging Face model folder, ~2.2 GB)

Why: the merged folder works in any tool that reads Hugging Face models, and it is
     what you convert to GGUF for Ollama / llama.cpp (see docs/03_python_cpu_commandline.md).

Run:  python scripts/export_merge.py
"""
import argparse
import os

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_MODEL = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
ADAPTER_DIR = os.path.join(ROOT, "models", "tinyllama-netshell-lora")
MERGED_DIR = os.path.join(ROOT, "models", "tinyllama-netshell-merged")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--adapter", default=ADAPTER_DIR)
    p.add_argument("--out", default=MERGED_DIR)
    args = p.parse_args()

    tok = AutoTokenizer.from_pretrained(args.model)
    base = AutoModelForCausalLM.from_pretrained(args.model, dtype=torch.float32)
    model = PeftModel.from_pretrained(base, args.adapter)
    merged = model.merge_and_unload()
    # save as bfloat16 to halve the size; safetensors is the standard format
    merged = merged.to(torch.bfloat16)
    os.makedirs(args.out, exist_ok=True)
    merged.save_pretrained(args.out, safe_serialization=True)
    tok.save_pretrained(args.out)
    print(f"merged model saved to {os.path.relpath(args.out, ROOT)}")
    print("next (optional): convert to GGUF, see docs/03_python_cpu_commandline.md step 7")


if __name__ == "__main__":
    main()
