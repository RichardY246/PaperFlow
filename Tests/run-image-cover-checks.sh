#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$(mktemp -d /private/tmp/paperflow-image-checks.XXXXXX)"
xcrun swiftc -module-cache-path "$output_path/ModuleCache" -parse-as-library "$project_dir"/PaperFlow/Models/*.swift "$project_dir/PaperFlow/Services/AIService.swift" "$project_dir/PaperFlow/Services/ImageGenerationService.swift" "$project_dir/Tests/ImageCoverChecks.swift" -o "$output_path/ImageCoverChecks"
cd "$project_dir"
"$output_path/ImageCoverChecks"
