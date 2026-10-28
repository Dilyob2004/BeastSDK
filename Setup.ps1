<#
Prepares the Beast build tool (Beast.BuildTool.v2 git submodule) for this repository.
  .\Setup.ps1                 fetch the submodule (if missing) and build it
  .\Setup.ps1 -InstallDotnet  also install the .NET 10 SDK when it is not found
  .\Setup.ps1 -Update         move the submodule to the latest commit of its branch (main)
  .\Setup.ps1 -Ref <branch>   check out a branch, tag or commit of Beast.BuildTool.v2 (testing
                              unmerged work; git status then shows the submodule as modified)
If scripts are blocked: powershell -ExecutionPolicy Bypass -File .\Setup.ps1
Then run the tool with .\beast.ps1 <command> ...
#>
param([switch]$InstallDotnet, [switch]$Update, [string]$Ref)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$tool = Join-Path $PSScriptRoot 'Beast.BuildTool.v2'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git was not found in PATH.' }
if ($Update) { git submodule update --init --remote Beast.BuildTool.v2 }
elseif (-not $Ref -or -not (Test-Path (Join-Path $tool '.git'))) { git submodule update --init --recursive Beast.BuildTool.v2 }
if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the Beast.BuildTool.v2 submodule.' }
if ($Ref) {
    git -C $tool fetch origin
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed in Beast.BuildTool.v2.' }
    git -C $tool rev-parse --verify --quiet "origin/$Ref" | Out-Null
    $commit = if ($LASTEXITCODE -eq 0) { "origin/$Ref" } else { $Ref }
    git -C $tool checkout --detach $commit
    if ($LASTEXITCODE -ne 0) { throw "Could not check out '$Ref' in Beast.BuildTool.v2." }
}

if ($InstallDotnet) { & (Join-Path $tool 'InstallDotnet.ps1') }
& cmd /c "`"$(Join-Path $tool 'Build.bat')`""
if ($LASTEXITCODE -ne 0) { throw 'Beast.BuildTool.v2 build failed (see output above). Missing .NET 10? Run .\Setup.ps1 -InstallDotnet' }
Write-Host ''
Write-Host "Beast build tool: $(Join-Path $tool 'BuildTool\bin\Beast.BuildTool.exe')  (run it with .\beast.ps1)"
