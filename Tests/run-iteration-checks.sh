#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-iteration-checks.XXXXXX)"
source "$project_dir/Tests/compile-support.sh"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "${model_sources[@]}" "${state_sources[@]}" "$project_dir/Tests/IterationChecks.swift" -o "$output_path/IterationChecks"
"$output_path/IterationChecks" "$project_dir/PaperFlow/Resources/DemoCatalog.json"
