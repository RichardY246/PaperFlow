#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-access-checks.XXXXXX)"
source "$project_dir/Tests/compile-support.sh"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "${model_sources[@]}" "${state_sources[@]}" "${service_sources[@]}" "${discovery_sources[@]}" "$project_dir/Tests/AccessMediaChecks.swift" -o "$output_path/AccessMediaChecks"
"$output_path/AccessMediaChecks" "$project_dir" "$output_path/artifacts"
