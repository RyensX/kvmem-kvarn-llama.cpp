#!/usr/bin/env bash
# Replay maintained diffs without commits or Git identity changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA="${KVMEM_LLAMA_DIR:-$ROOT/llama.cpp}"
PATCH="$ROOT/patches/llama-kvmem-current.patch"
WINDOWS_UPGRADE="$ROOT/patches/windows-jinja-encoding-upgrade.patch"
PIN="78af8326522d94fb5fc24b60cfd6f26e29f12490"
cd "$LLAMA"

if [[ -d .git || -f .git ]]; then
    head="$(git rev-parse HEAD)"
    if [[ "$head" != "$PIN" ]]; then
        echo "llama.cpp is at $head; expected $PIN" >&2
        echo "run: git submodule sync --recursive && git submodule update --init --force --checkout llama.cpp" >&2
        exit 1
    fi
fi

if git apply --reverse --check "$PATCH" 2>/dev/null; then
    echo "KVMem patches already applied"
elif git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
    echo "applied KVMem runtime patch to BeeLlama $PIN"
elif git apply --check "$WINDOWS_UPGRADE" 2>/dev/null; then
    git apply "$WINDOWS_UPGRADE"
    if ! git apply --reverse --check "$PATCH" 2>/dev/null; then
        echo "incremental Windows encoding upgrade did not produce the supported tree" >&2
        exit 1
    fi
    echo "upgraded existing KVMem tree with Windows encoding fix"
else
    echo "llama.cpp differs from the supported pin or already-patched tree; no files changed" >&2
    exit 1
fi
