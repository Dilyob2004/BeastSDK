#!/usr/bin/env bash
# Prepares the Beast build tool (Beast.BuildTool.v2 git submodule) on Linux/macOS.
#   ./Setup.sh                   fetch the submodule (if missing) and build it
#   ./Setup.sh --install-dotnet  also install the .NET 10 SDK when it is not found
#   ./Setup.sh --android         also install the Android toolchain (JDK 17, SDK, NDK) via InstallAndroid.sh
#   ./Setup.sh --android --emulator   ... plus the emulator and AVD beast_api34
#   ./Setup.sh --update          move the submodule to the latest commit of its branch (main)
#   ./Setup.sh --ref <branch>    check out a branch, tag or commit of Beast.BuildTool.v2 (unmerged work)
# Then run the tool with ./beast.sh <command> ...
set -euo pipefail
cd "$(dirname "$0")"
install=0; android=0; emulator=0; update=0; ref=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dotnet) install=1;;
        --android) android=1;;
        --emulator) emulator=1;;
        --update) update=1;;
        --ref) ref="${2:?--ref needs a branch, tag or commit}"; shift;;
        *) echo "Unknown option: $1"; exit 2;;
    esac
    shift
done
if [[ $update -eq 1 ]]; then git submodule update --init --remote Beast.BuildTool.v2
elif [[ -z "$ref" || ! -e Beast.BuildTool.v2/.git ]]; then git submodule update --init --recursive Beast.BuildTool.v2; fi
if [[ -n "$ref" ]]; then
    git -C Beast.BuildTool.v2 fetch origin
    if git -C Beast.BuildTool.v2 rev-parse --verify --quiet "origin/$ref" >/dev/null; then ref="origin/$ref"; fi
    git -C Beast.BuildTool.v2 checkout --detach "$ref"
fi
if [[ $install -eq 1 ]]; then bash Beast.BuildTool.v2/InstallDotnet.sh; fi
if [[ $android -eq 1 ]]; then
    if [[ $emulator -eq 1 ]]; then bash Beast.BuildTool.v2/InstallAndroid.sh --emulator; else bash Beast.BuildTool.v2/InstallAndroid.sh; fi
fi
bash Beast.BuildTool.v2/Build.sh
