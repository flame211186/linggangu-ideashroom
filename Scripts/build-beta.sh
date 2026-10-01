#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -m)" == "arm64" ]] || { echo "This Beta artifact targets Apple Silicon only." >&2; exit 2; }
output_dir="${1:-${project_dir}/dist}"
mkdir -p "${output_dir}"
output_dir="$(cd "${output_dir}" && pwd)"
work_dir="$(mktemp -d /private/tmp/linggangu-beta.XXXXXX)"
trap 'rm -rf "${work_dir}"' EXIT
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${project_dir}/Packaging/Info.plist")"
archive_name="LingGanGu-${version}-beta-macos-arm64.zip"
[[ ! -e "${output_dir}/${archive_name}" ]] || { echo "Output exists; choose a fresh directory." >&2; exit 2; }
env LINGGANGU_BUILD_CONFIGURATION=release LINGGANGU_SIGNING_IDENTITY=- \
    bash "${project_dir}/Scripts/package-local-app.sh" "${work_dir}"
codesign --verify --deep --strict "${work_dir}/灵感菇.app"
ditto -c -k --keepParent "${work_dir}/灵感菇.app" "${output_dir}/${archive_name}"
(cd "${output_dir}" && shasum -a 256 "${archive_name}" > "${archive_name}.sha256")
printf 'Created %s\n' "${output_dir}/${archive_name}"
