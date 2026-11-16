#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-service-checks.XXXXXX)"
source "$project_dir/Tests/compile-support.sh"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "${model_sources[@]}" "${service_sources[@]}" "$project_dir/Tests/ServiceChecks.swift" -o "$output_path/ServiceChecks"
"$output_path/ServiceChecks" "$@"
