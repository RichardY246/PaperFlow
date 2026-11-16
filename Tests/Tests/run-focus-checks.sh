#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /private/tmp/paperflow-focus.XXXXXX)"
python3 - "$project_dir" "$check_dir" <<'PY'
from pathlib import Path
import sys,shutil
project=Path(sys.argv[1]);root=Path(sys.argv[2]);sources=root/'Sources'/'Focus';sources.mkdir(parents=True)
for source in (project/'PaperFlow'/'Models').glob('*.swift'):shutil.copy(source,sources/source.name)
files=['Data/StateDatabase.swift','Data/AppStore.swift','Data/InterestStore.swift','Data/OnlineMigration.swift','Data/UsageStore.swift','Services/RecommendationEngine.swift','Services/AIService.swift','Services/PaperFileService.swift','Services/FigureExtractor.swift','Services/CoverPipeline.swift']
for name in files:shutil.copy(project/'PaperFlow'/name,sources/Path(name).name)
shutil.copy(project/'Tests/FocusChecks.swift',sources/'main.swift')
# @main 和文件名 main.swift 不能同时使用。
(sources/'main.swift').rename(sources/'FocusChecks.swift')
package=Path('/private/tmp/PaperFlow-1.7/SourcePackages/checkouts/SwiftSoup')
(root/'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name:"Focus",platforms:[.macOS(.v14)],dependencies:[.package(path:'+repr(str(package)).replace("'",'"')+')],targets:[.executableTarget(name:"Focus",dependencies:[.product(name:"SwiftSoup",package:"SwiftSoup")],linkerSettings:[.linkedLibrary("sqlite3")])],swiftLanguageModes:[.v5])')
PY
swift run --package-path "$check_dir" Focus "$project_dir" "$check_dir/artifacts"
