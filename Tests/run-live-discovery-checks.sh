#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-live-checks.XXXXXX)"
source "$project_dir/Tests/compile-support.sh"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "${model_sources[@]}" "${service_sources[@]}" "$project_dir/PaperFlow/Services/FederatedLiteratureService.swift" "$project_dir/PaperFlow/Services/LiteratureDecoders.swift" "$project_dir/PaperFlow/Services/OpenRepositoryDecoders.swift" "$project_dir/PaperFlow/Services/PaperFileService.swift" "$project_dir/Tests/LiveDiscoveryChecks.swift" -o "$output_path/LiveDiscoveryChecks"
"$output_path/LiveDiscoveryChecks"
