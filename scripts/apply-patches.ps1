$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Llama = if ($env:KVMEM_LLAMA_DIR) { $env:KVMEM_LLAMA_DIR } else { Join-Path $Root "llama.cpp" }
$Patch = Join-Path $Root "patches/llama-kvmem-current.patch"
$WindowsUpgrade = Join-Path $Root "patches/windows-jinja-encoding-upgrade.patch"
$Pin = "78af8326522d94fb5fc24b60cfd6f26e29f12490"

Push-Location $Llama
try {
    $Head = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $Head -ne $Pin) {
        throw "llama.cpp is at $Head; expected $Pin; run git submodule sync --recursive followed by git submodule update --init --force --checkout llama.cpp"
    }

    git apply --reverse --check $Patch 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "KVMem patches already applied"
        exit 0
    }

    git apply --check $Patch 2>$null
    if ($LASTEXITCODE -eq 0) {
        git apply $Patch
        if ($LASTEXITCODE -ne 0) { throw "failed to apply KVMem runtime patch" }
        Write-Host "applied KVMem runtime patch to BeeLlama $Pin"
        exit 0
    }

    git apply --check $WindowsUpgrade 2>$null
    if ($LASTEXITCODE -eq 0) {
        git apply $WindowsUpgrade
        if ($LASTEXITCODE -ne 0) { throw "failed to apply Windows encoding upgrade" }
        git apply --reverse --check $Patch 2>$null
        if ($LASTEXITCODE -ne 0) { throw "incremental Windows encoding upgrade did not produce the supported tree" }
        Write-Host "upgraded existing KVMem tree with Windows encoding fix"
        exit 0
    }

    throw "llama.cpp differs from the supported pin or already-patched tree"
}
finally {
    Pop-Location
}
