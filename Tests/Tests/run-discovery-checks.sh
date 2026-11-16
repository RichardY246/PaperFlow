#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-discovery-checks.XXXXXX)"
source "$project_dir/Tests/compile-support.sh"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "${model_sources[@]}" "${state_sources[@]}" "${service_sources[@]}" "${discovery_sources[@]}" "$project_dir/Tests/DiscoveryChecks.swift" -o "$output_path/DiscoveryChecks"
"$output_path/DiscoveryChecks" "${1:-}" "$project_dir/PaperFlow/Resources/DemoCatalog.json"
