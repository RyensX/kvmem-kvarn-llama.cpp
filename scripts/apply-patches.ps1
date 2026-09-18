$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Llama = if ($env:KVMEM_LLAMA_DIR) { $env:KVMEM_LLAMA_DIR } else { Join-Path $Root "llama.cpp" }
$Patch = Join-Path $Root "patches/llama-kvmem-current.patch"
$Pin = "78af8326522d94fb5fc24b60cfd6f26e29f12490"

Push-Location $Llama
try {
    git apply --reverse --check $Patch 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "KVMem patches already applied"
        exit 0
    }

    git apply --check $Patch
    if ($LASTEXITCODE -ne 0) {
        throw "llama.cpp differs from the supported pin or already-patched tree"
    }

    $Head = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $Head -ne $Pin) {
        throw "llama.cpp is at $Head; expected $Pin"
    }

    git apply $Patch
    if ($LASTEXITCODE -ne 0) {
        throw "failed to apply KVMem runtime patch"
    }
    Write-Host "applied KVMem runtime patch to BeeLlama $Pin"
}
finally {
    Pop-Location
}
