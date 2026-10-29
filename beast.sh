#!/usr/bin/env bash
# Runs the Beast build tool from the Beast.BuildTool.v2 submodule. Prepare it once with ./Setup.sh.
tool="$(cd "$(dirname "$0")" && pwd)/Beast.BuildTool.v2/BuildTool/bin/Beast.BuildTool"
[[ -x "$tool" ]] || { echo "Beast build tool is not built: run ./Setup.sh first ($tool)" >&2; exit 1; }
exec "$tool" "$@"
