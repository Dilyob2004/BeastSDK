<#
Runs the Beast build tool from the Beast.BuildTool.v2 submodule. Prepare it once with .\Setup.ps1.
  .\beast.ps1 build Test/EcoSbor --platform Windows --config Debug
  .\beast.ps1 new MyApp --path Test --template BeastSDK/Templates/UIApplication
#>
$tool = Join-Path $PSScriptRoot 'Beast.BuildTool.v2\BuildTool\bin\Beast.BuildTool.exe'
if (-not (Test-Path $tool)) { Write-Error "Beast build tool is not built: run .\Setup.ps1 first ($tool)"; exit 1 }
& $tool @args
exit $LASTEXITCODE
