#!/usr/bin/env bash
# Turn this repository into a NEW project:  ./scripts/new-project-from-template.sh my-shop ../my-shop
# It copies the repo (minus build artefacts), renames "python-demo" -> "my-shop" everywhere
# (app.config.yaml, Helm chart, k8s manifests, docs, terraform), and resets versions/history.
set -euo pipefail
NEW="${1:?usage: $0 <new-name> <destination-dir>}"; DEST="${2:?usage: $0 <new-name> <destination-dir>}"
[[ "$NEW" =~ ^[a-z0-9]([-a-z0-9]{0,38}[a-z0-9])?$ ]] || { echo "name must be a DNS label (lowercase, digits, dashes)"; exit 1; }
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLD="$(python3 "$SRC/tools/appconfig.py" get name -c "$SRC/app.config.yaml")"
[[ -e "$DEST" ]] && { echo "destination exists: $DEST"; exit 1; }
mkdir -p "$DEST"
# copy everything except generated / local files
tar -C "$SRC" --exclude=./build --exclude=./.git --exclude=./.terraform --exclude='*.tfstate*' \
    --exclude=./secrets.env --exclude=./.env --exclude='__pycache__' --exclude='./ansible/inventory/*.ini' -cf - . | tar -C "$DEST" -xf -
# rename: python-demo -> new name, python_demo -> new_name (only in text files)
NEW_US="${NEW//-/_}"; OLD_US="${OLD//-/_}"
grep -rIl --exclude-dir=.git -e "$OLD" -e "$OLD_US" "$DEST" | while read -r f; do
  sed -i.bak -e "s/$OLD_US/$NEW_US/g" -e "s/$OLD/$NEW/g" "$f" && rm -f "$f.bak"
done
[[ -d "$DEST/helm/$OLD" ]] && mv "$DEST/helm/$OLD" "$DEST/helm/$NEW"
cp "$DEST/secrets.env.example" "$DEST/secrets.env" 2>/dev/null || true
cd "$DEST" && python3 tools/appconfig.py validate && git init -q . && git add -A && git commit -qm "Bootstrap $NEW from template" \
  && echo "Created $DEST (project '$NEW'). Next: edit app.config.yaml, then ./scripts/run-all.sh"
