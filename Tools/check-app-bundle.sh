#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-bundle-checks.XXXXXX)"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "$project_dir/Tools/CheckAppBundle.swift" -o "$output_path/check"
"$output_path/check" "$1"
