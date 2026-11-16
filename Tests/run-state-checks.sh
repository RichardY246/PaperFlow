#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-checks.XXXXXX)"
source "$project_dir/Tests/compile-support.sh"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "${model_sources[@]}" "${state_sources[@]}" "$project_dir/Tests/StateChecks.swift" -o "$output_path/StateChecks"
"$output_path/StateChecks" "$project_dir/Tests/Fixtures/LegacyCatalog.json"
