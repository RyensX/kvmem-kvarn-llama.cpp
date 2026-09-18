# llama.cpp patch replay

`llama.cpp` remains a submodule, pinned to BeeLlama
`78af8326522d94fb5fc24b60cfd6f26e29f12490`. The main repository owns the
KVMem integration as `llama-kvmem-current.patch`; upstream source is not
vendored into the main repository.

`scripts/apply-patches.sh` and `scripts/apply-patches.ps1` apply the cumulative
patch without creating commits. Both are repeatable and reject an unexpected
submodule revision or a partially modified tree.

`windows-jinja-encoding-upgrade.patch` upgrades a tree that had the preceding
cumulative patch applied before the Windows source-encoding fix.

To check a clean extraction without changing the active submodule:

```bash
mkdir -p /tmp/kvmem-llama-patch-check
git -C llama.cpp archive 78af832 | tar -x -C /tmp/kvmem-llama-patch-check
KVMEM_LLAMA_DIR=/tmp/kvmem-llama-patch-check scripts/apply-patches.sh
KVMEM_LLAMA_DIR=/tmp/kvmem-llama-patch-check scripts/apply-patches.sh
```
