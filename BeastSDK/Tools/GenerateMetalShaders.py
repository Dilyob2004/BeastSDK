#!/usr/bin/env python3
"""Adds Metal Shading Language (MSL) to the generated UI shaders.

Reads every shader in BeastSDK/Source/UI/Private/UIShaders.generated.h, converts its SPIR-V with
SPIRV-Cross (https://github.com/KhronosGroup/SPIRV-Cross) and writes `d.msl = R"..."` next to the
GLSL targets. Run it after GenerateUIAssets (which rewrites the header without MSL):

    python3 BeastSDK/Tools/GenerateMetalShaders.py [--spirv-cross <path>]

Conventions shared with RHI/Private/Metal/MetalRHI.mm:
  * MSL 2.1 (iOS 12+, macOS 10.14+); one source serves iOS, the iOS Simulator and macOS.
  * Vertex shaders use --flip-vert-y: RHI vertices have Y pointing down (the Vulkan convention),
    Metal's clip space has Y up. Render targets and textures both keep row 0 at the top, so
    offscreen layers need no extra flip.
  * Stage inputs are [[attribute(0..2)]] (position, uv, color) from vertex buffer 0; fragment
    resources are texture(0), sampler(0) and the draw constants in buffer(0).
"""
import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HEADER = os.path.join(HERE, "..", "Source", "UI", "Private", "UIShaders.generated.h")
MSL_VERSION = "20100"
DELIMITER = "BEAST_MSL"


def convert(spirv_cross, words, vertex):
    with tempfile.TemporaryDirectory() as work:
        source = os.path.join(work, "shader.spv")
        with open(source, "wb") as file:
            file.write(struct.pack("<%dI" % len(words), *words))
        command = [spirv_cross, source, "--msl", "--msl-version", MSL_VERSION]
        if vertex:
            command.append("--flip-vert-y")
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit("spirv-cross failed:\n" + result.stderr)
        if ")" + DELIMITER + '"' in result.stdout:
            sys.exit("MSL output contains the raw string delimiter.")
        return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--spirv-cross", default=shutil.which("spirv-cross"), help="path to the spirv-cross executable")
    parser.add_argument("--header", default=HEADER)
    args = parser.parse_args()
    if not args.spirv_cross:
        sys.exit("spirv-cross was not found: build SPIRV-Cross and pass --spirv-cross <path>.")

    text = open(args.header, encoding="utf-8").read()
    # Previous MSL blocks are replaced, so the script can run repeatedly.
    text = re.sub(r'    d\.msl = R"%s\(.*?\)%s";\n' % (DELIMITER, DELIMITER), "", text, flags=re.S)
    pattern = re.compile(r'(d\.name = "(\w+)"; d\.stage = Beast::RHIShaderStage::(\w+);.*?d\.spirv = \{(.*?)\};.*?)(\n    d\.combinedSampler)', re.S)
    count = 0

    def add(match):
        nonlocal count
        words = [int(word.strip().rstrip("u"), 16) for word in match.group(4).split(",") if word.strip()]
        msl = convert(args.spirv_cross, words, match.group(3) == "Vertex")
        count += 1
        return match.group(1) + '\n    d.msl = R"%s(%s)%s";' % (DELIMITER, msl, DELIMITER) + match.group(5)

    text = pattern.sub(add, text)
    if count == 0:
        sys.exit("No shaders found in " + args.header)
    with open(args.header, "w", encoding="utf-8", newline="\n") as file:
        file.write(text)
    print("MSL added to %d shaders: %s" % (count, os.path.normpath(args.header)))


if __name__ == "__main__":
    main()
