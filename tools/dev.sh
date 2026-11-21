#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${HAVU_GODOT:-godot}"
if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo 'Godot 4.7 is required. Set HAVU_GODOT to its executable path.' >&2
  exit 1
fi
case "${1:-run}" in
  editor) exec "$godot_bin" --path "$project_dir" --editor ;;
  run) exec "$godot_bin" --path "$project_dir" ;;
  *) echo 'Usage: tools/dev.sh [run|editor]' >&2; exit 2 ;;
esac
