$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Llama = if ($env:KVMEM_LLAMA_DIR) { $env:KVMEM_LLAMA_DIR } else { Join-Path $Root "llama.cpp" }
$Patch = Join-Path $Root "patches/llama-kvmem-current.patch"
$WindowsUpgrade = Join-Path $Root "patches/windows-jinja-encoding-upgrade.patch"
$Pin = "78af8326522d94fb5fc24b60cfd6f26e29f12490"

function Test-GitApply {
    param([string[]]$Arguments)
    $SavedPreference = $ErrorActionPreference
    try {
        # A failed applicability probe is expected, including stderr on PS 5.1.
        $ErrorActionPreference = "Continue"
        git apply @Arguments 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    }
    finally { $ErrorActionPreference = $SavedPreference }
}

if (!(Test-Path (Join-Path $Llama '.git')) -or !(Test-Path (Join-Path $Llama 'CMakeLists.txt'))) {
    throw "Runtime submodule is not initialized: $Llama"
}
Push-Location $Llama
try {
    $Head = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $Head -ne $Pin) {
        throw "llama.cpp is at $Head; expected $Pin; run git submodule sync --recursive followed by git submodule update --init --force --checkout llama.cpp"
    }

    if (Test-GitApply @('--reverse', '--check', $Patch)) {
        Write-Host "KVMem patches already applied"
        exit 0
    }

    if (Test-GitApply @('--check', $Patch)) {
        git apply $Patch
        if ($LASTEXITCODE -ne 0) { throw "failed to apply KVMem runtime patch" }
        if (!(Test-GitApply @('--reverse', '--check', $Patch))) { throw "runtime patch verification failed" }
        Write-Host "applied KVMem runtime patch to BeeLlama $Pin"
        exit 0
    }

    if ((Test-GitApply @('--reverse', '--check', '--exclude=common/jinja/utils.h', $Patch)) -and (Test-GitApply @('--check', $WindowsUpgrade))) {
        git apply $WindowsUpgrade
        if ($LASTEXITCODE -ne 0) { throw "failed to apply Windows encoding upgrade" }
        if (!(Test-GitApply @('--reverse', '--check', $Patch))) { throw "incremental Windows encoding upgrade did not produce the supported tree" }
        Write-Host "upgraded existing KVMem tree with Windows encoding fix"
        exit 0
    }

    throw "llama.cpp differs from the supported pin or already-patched tree"
}
finally {
    Pop-Location
}
