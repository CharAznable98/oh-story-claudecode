#!/usr/bin/env bash
# Lightweight checks for the official Codex plugin/marketplace compatibility layer.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKETPLACE_JSON="$REPO_ROOT/.agents/plugins/marketplace.json"
PLUGIN_DIR="$REPO_ROOT"
PLUGIN_JSON="$PLUGIN_DIR/.codex-plugin/plugin.json"
PLUGIN_SKILLS_DIR="$PLUGIN_DIR/skills"

expected_skills=(
  browser-cdp
  story
  story-cover
  story-deslop
  story-import
  story-long-analyze
  story-long-scan
  story-long-write
  story-review
  story-setup
  story-short-analyze
  story-short-scan
  story-short-write
)

python_bin=""
for candidate in python3 python py; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "" >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
if [ -z "$python_bin" ]; then
  echo "Error: no usable Python interpreter found" >&2
  exit 1
fi

if [ ! -f "$MARKETPLACE_JSON" ]; then
  echo "Error: missing Codex marketplace: $MARKETPLACE_JSON" >&2
  exit 1
fi
if [ ! -f "$PLUGIN_JSON" ]; then
  echo "Error: missing Codex plugin manifest: $PLUGIN_JSON" >&2
  exit 1
fi

"$python_bin" - <<'PY' "$MARKETPLACE_JSON" "$PLUGIN_JSON" "$REPO_ROOT" "$PLUGIN_DIR"
import json
import pathlib
import sys

marketplace_json = pathlib.Path(sys.argv[1])
plugin_json = pathlib.Path(sys.argv[2])
repo_root = pathlib.Path(sys.argv[3]).resolve()
plugin_dir = pathlib.Path(sys.argv[4]).resolve()

with marketplace_json.open("r", encoding="utf-8") as fh:
    marketplace = json.load(fh)
with plugin_json.open("r", encoding="utf-8") as fh:
    manifest = json.load(fh)

if marketplace.get("name") != "oh-story-plugins":
    raise SystemExit("Error: unexpected marketplace name")
plugins = marketplace.get("plugins")
if not isinstance(plugins, list) or len(plugins) != 1:
    raise SystemExit("Error: marketplace must contain exactly one plugin entry")
entry = plugins[0]
if entry.get("name") != manifest.get("name"):
    raise SystemExit("Error: marketplace plugin name must match plugin.json name")
source = entry.get("source")
if not isinstance(source, dict) or source.get("source") != "local":
    raise SystemExit("Error: marketplace source must be a local source object")
source_path = source.get("path")
if source_path != "./":
    raise SystemExit("Error: marketplace source.path must point at repo root ./")
if (repo_root / source_path).resolve() != plugin_dir:
    raise SystemExit("Error: marketplace source.path does not resolve to the repo-root plugin directory")
if not (plugin_dir / ".codex-plugin" / "plugin.json").is_file():
    raise SystemExit("Error: repo-root plugin directory must contain .codex-plugin/plugin.json")
for key in ["policy", "category"]:
    if key not in entry:
        raise SystemExit(f"Error: marketplace plugin entry missing {key}")

required = ["name", "version", "description", "skills", "interface"]
missing = [key for key in required if key not in manifest]
if missing:
    raise SystemExit(f"Error: plugin.json missing required fields: {', '.join(missing)}")

skills_value = manifest["skills"]
if skills_value != "./skills/":
    raise SystemExit("Error: plugin.json skills must be ./skills/ for repo-root plugin packaging")

raw_skills_dir = plugin_dir / skills_value
if raw_skills_dir.is_symlink():
    raise SystemExit("Error: plugin skills path must be the real repo skills directory, not a symlink")
skills_dir = raw_skills_dir.resolve()
if skills_dir != (repo_root / "skills").resolve():
    raise SystemExit(f"Error: plugin skills path must resolve to repo skills/: {skills_dir}")
if not skills_dir.is_dir():
    raise SystemExit(f"Error: plugin.json skills path does not exist: {skills_dir}")

interface = manifest["interface"]
for key in ["displayName", "shortDescription", "defaultPrompt"]:
    if key not in interface:
        raise SystemExit(f"Error: plugin.json interface missing {key}")

prompts = interface["defaultPrompt"]
if not isinstance(prompts, list) or len(prompts) > 3:
    raise SystemExit("Error: interface.defaultPrompt must be a list of at most 3 prompts")
PY

for name in "${expected_skills[@]}"; do
  skill_md="$PLUGIN_SKILLS_DIR/$name/SKILL.md"
  if [ ! -f "$skill_md" ]; then
    echo "Error: missing skill through plugin path: $name at $skill_md" >&2
    exit 1
  fi

  if ! grep -q '^name:[[:space:]]' "$skill_md" || ! grep -q '^description:' "$skill_md"; then
    echo "Error: invalid frontmatter in $skill_md (expected name and description)" >&2
    exit 1
  fi

  agent_yaml="$PLUGIN_SKILLS_DIR/$name/agents/openai.yaml"
  if [ ! -f "$agent_yaml" ]; then
    echo "Error: missing Codex agent metadata through plugin path: $agent_yaml" >&2
    exit 1
  fi

  for field in 'display_name:' 'short_description:' 'default_prompt:'; do
    if ! grep -q "$field" "$agent_yaml"; then
      echo "Error: $agent_yaml missing $field" >&2
      exit 1
    fi
  done
done

echo "Codex plugin smoke test passed: marketplace -> repo-root plugin -> ${#expected_skills[@]} skills"
