#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="$(mktemp -d "${TMPDIR:-/tmp}/havu-tests.XXXXXX")"
trap 'rm -rf -- "$state_dir"' EXIT
export XDG_DATA_HOME="$state_dir/data"
export XDG_CONFIG_HOME="$state_dir/config"
export XDG_CACHE_HOME="$state_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot_bin="${HAVU_GODOT:-godot}"
timeout 60 "$godot_bin" --path "$project_dir" --headless --editor --import --quit > "$state_dir/import.log" 2>&1
if rg -q 'SCRIPT ERROR|Parse Error|Failed to load script' "$state_dir/import.log"; then
  cat "$state_dir/import.log"
  exit 1
fi
timeout 30 "$godot_bin" --path "$project_dir" --headless --script res://tests/test_app.gd -- --test > "$state_dir/tests.log" 2>&1 || {
  cat "$state_dir/tests.log"
  exit 1
}
cat "$state_dir/tests.log"
if rg -q 'SCRIPT ERROR|ERROR:|FAIL:' "$state_dir/tests.log"; then
  exit 1
fi
