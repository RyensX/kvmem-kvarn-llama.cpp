[CmdletBinding()]
param(
    [string]$CudaPath = $env:CUDA_PATH,
    [string]$BuildDir = "",
    [ValidatePattern('^[0-9]+[a-z]?(-real)?$')][string]$Architecture = "89-real",
    [ValidateRange(1, 256)][int]$Jobs = 8
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    $SavedPreference = $ErrorActionPreference
    try {
        # Native tools may write progress to stderr even on success (PS 5.1).
        $ErrorActionPreference = "Continue"
        & $Program @Arguments
        $Code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $SavedPreference }
    if ($Code -ne 0) { throw "$Program failed (exit $Code). Build stopped." }
}

Push-Location $Root
try {
    if ($env:OS -ne "Windows_NT") { throw "Run this script on Windows." }
    $Git = (Get-Command git -ErrorAction Stop).Source
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (!(Test-Path $VsWhere)) { throw "Install Visual Studio 2022 with Desktop development with C++." }
    $VsPath = & $VsWhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or !$VsPath) { throw "Visual Studio 2022 C++ x64 tools not found." }
    $CMakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    $CMake = if ($CMakeCommand) { $CMakeCommand.Source } else { Join-Path $VsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" }
    if (!(Test-Path $CMake)) { throw "Install CMake or enable C++ CMake tools in Visual Studio." }

    if (!$CudaPath) { $CudaPath = Join-Path $env:ProgramFiles "NVIDIA GPU Computing Toolkit\CUDA\v13.2" }
    $CudaPath = (Resolve-Path $CudaPath).Path
    $Nvcc = Join-Path $CudaPath "bin\nvcc.exe"
    $VersionText = & $Nvcc --version
    if ($LASTEXITCODE -ne 0) { throw "Cannot run $Nvcc" }
    $Match = [regex]::Match(($VersionText -join "`n"), 'V(\d+\.\d+\.\d+)')
    if (!$Match.Success -or [version]$Match.Groups[1].Value -lt [version]'13.2.86') {
        throw "CUDA nvcc 13.2.86 or newer required. Select another installation with -CudaPath."
    }
    $Version = $Match.Groups[1].Value
    if (!$BuildDir) { $BuildDir = "build-win-cuda-$Version-$Architecture" }
    if (![IO.Path]::IsPathRooted($BuildDir)) { $BuildDir = Join-Path $Root $BuildDir }
    $BuildDir = [IO.Path]::GetFullPath($BuildDir)
    Write-Host "CUDA $Version | architecture $Architecture | jobs $Jobs"
    Write-Host "Build directory: $BuildDir"

    Invoke-Checked $Git @('submodule', 'sync', '--recursive')
    # Never force a checkout or discard local runtime modifications.
    Invoke-Checked $Git @('submodule', 'update', '--init', '--recursive')
    # Use a child process because the patch helper returns a process exit code.
    $PowerShell = Join-Path $PSHOME 'powershell.exe'
    if (!(Test-Path $PowerShell)) { $PowerShell = Join-Path $PSHOME 'pwsh.exe' }
    $SavedRuntime = $env:KVMEM_LLAMA_DIR
    try {
        $env:KVMEM_LLAMA_DIR = Join-Path $Root 'llama.cpp'
        Invoke-Checked $PowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'apply-patches.ps1'))
    }
    finally { $env:KVMEM_LLAMA_DIR = $SavedRuntime }

    $Required = @{
        'include/llama.h' = 'logical_pos'
        'tools/server/server-common.h' = 'oaicompat_chat_process_media'
        'tools/mtmd/mtmd-helper.h' = 'mtmd_helper_decode_image_chunk_with_decoder'
        'common/speculative.h' = 'n_past_logical'
    }
    foreach ($Header in $Required.Keys) {
        $File = Join-Path (Join-Path $Root 'llama.cpp') $Header
        if (!(Select-String -Path $File -SimpleMatch -Pattern $Required[$Header] -Quiet)) {
            throw "Required interface $($Required[$Header]) missing in $File. Build stopped."
        }
    }
    Invoke-Checked $CMake @('-S', $Root, '-B', $BuildDir, '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', "cuda=$CudaPath", "-DCMAKE_GENERATOR_INSTANCE=$VsPath", '-DGGML_CUDA=ON', '-DGGML_NATIVE=ON', '-DGGML_CUDA_FA=ON', '-DGGML_CUDA_KVARN=ON', '-DGGML_CUDA_FA_ALL_QUANTS=ON', "-DCMAKE_CUDA_ARCHITECTURES=$Architecture", '-DKVMEM_BUILD_LLAMA=ON')
    Invoke-Checked $CMake @('--build', $BuildDir, '--config', 'Release', '--target', 'llama-kvmem-server', '--parallel', "$Jobs")
    $Server = Join-Path $BuildDir 'bin\Release\llama-kvmem-server.exe'
    if (!(Test-Path $Server)) { throw "Build returned success but server executable is missing: $Server" }
    Write-Host "Build complete: $Server"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally { Pop-Location }
