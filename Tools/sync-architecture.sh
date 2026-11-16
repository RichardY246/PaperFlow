#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
assignment_dir="$(cd "$project_dir/../.." && pwd)"
cp "$project_dir/Docs/页面架构.md" "$assignment_dir/PaperFlow_页面架构与按钮跳转_草稿.md"
