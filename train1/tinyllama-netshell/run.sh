#!/usr/bin/env bash
# One-command version of the Python path. Run from the project folder:  bash run.sh
set -e
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  echo "== creating virtual environment (.venv)"
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

echo "== installing packages (first time only takes a few minutes)"
pip install -q --upgrade pip
pip install -q -r requirements.txt

echo "== building the dataset"
python scripts/build_dataset.py

echo "== training (no GPU needed; go get a snack)"
python scripts/train_cpu.py "$@"

echo "== testing"
python scripts/chat_test.py
