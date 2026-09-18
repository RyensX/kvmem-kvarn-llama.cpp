#!/usr/bin/env bash
# Replay maintained diffs without commits or Git identity changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA="${KVMEM_LLAMA_DIR:-$ROOT/llama.cpp}"
PATCH="$ROOT/patches/llama-kvmem-current.patch"
PIN="78af8326522d94fb5fc24b60cfd6f26e29f12490"
cd "$LLAMA"

if git apply --reverse --check "$PATCH" 2>/dev/null; then
    echo "KVMem patches already applied"
elif git apply --check "$PATCH" 2>/dev/null; then
    if [[ -d .git || -f .git ]]; then
        head="$(git rev-parse HEAD)"
        if [[ "$head" != "$PIN" ]]; then
            echo "llama.cpp is at $head; expected $PIN" >&2
            exit 1
        fi
    fi
    git apply "$PATCH"
    echo "applied KVMem runtime patch to BeeLlama $PIN"
else
    echo "llama.cpp differs from the supported pin or already-patched tree; no files changed" >&2
    exit 1
fi
