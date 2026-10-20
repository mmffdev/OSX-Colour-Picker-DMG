#!/bin/bash
set -euo pipefail
base="$(cd "$(dirname "$0")" && pwd)"
output="$base/../../.build/lightroom/Colorgain.lrplugin"
mkdir -p "$output"
cp "$base/Colorgain.lrplugin/"*.lua "$output/"
/usr/bin/swiftc -O "$base/MetadataReader.swift" -o "$output/ColorgainMetadataReader"
printf '%s\n' "$output"
