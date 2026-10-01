#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
install_dir="${1:-${HOME}/Applications}"
scratch_dir="${LINGGANGU_SCRATCH_DIR:-/private/tmp/linggangu-local-app-build}"
module_cache_dir="${LINGGANGU_MODULE_CACHE_DIR:-/private/tmp/linggangu-local-app-module-cache}"
staging_dir="$(mktemp -d /private/tmp/linggangu-app-package.XXXXXX)"
staging_app="${staging_dir}/灵感菇.app"
installed_app="${install_dir}/灵感菇.app"
build_configuration="${LINGGANGU_BUILD_CONFIGURATION:-debug}"
case "${build_configuration}" in debug|release) ;; *) exit 2 ;; esac

cleanup() {
    rm -rf "${staging_dir}"
}
trap cleanup EXIT

env \
    CLANG_MODULE_CACHE_PATH="${module_cache_dir}/clang" \
    SWIFTPM_MODULECACHE_OVERRIDE="${module_cache_dir}/swiftpm" \
    swift build \
        --package-path "${project_dir}" \
        --scratch-path "${scratch_dir}" \
        --configuration "${build_configuration}" \
        -Xswiftc -debug-prefix-map -Xswiftc "${project_dir}=." \
        --disable-sandbox \
        --product LingGanGu

build_dir="$(swift build --package-path "${project_dir}" --scratch-path "${scratch_dir}" --configuration "${build_configuration}" --show-bin-path)"

mkdir -p \
    "${staging_app}/Contents/MacOS" \
    "${staging_app}/Contents/Resources" \
    "${staging_app}/AppIcon.iconset"

cp "${project_dir}/Packaging/Info.plist" "${staging_app}/Contents/Info.plist"
cp "${project_dir}/LICENSE" "${project_dir}/NOTICE.md" "${project_dir}/THIRD_PARTY_NOTICES.md" "${staging_app}/Contents/Resources/"
cp "${build_dir}/LingGanGu" "${staging_app}/Contents/MacOS/LingGanGu"
if [[ "${build_configuration}" == "release" ]]; then
    strip -S "${staging_app}/Contents/MacOS/LingGanGu"
fi
chmod 755 "${staging_app}/Contents/MacOS/LingGanGu"

cp -R \
    "${build_dir}/LingGanGu_LingGanGuApp.bundle" \
    "${staging_app}/Contents/Resources/LingGanGu_LingGanGuApp.bundle"

icon_source="${project_dir}/docs/design/assets/linggangu-mushroom-base.png"
square_icon="${staging_dir}/app-icon-square.png"
sips --cropToHeightWidth 1360 1360 "${icon_source}" --out "${square_icon}" >/dev/null

make_icon() {
    local pixels="$1"
    local filename="$2"
    sips -z "${pixels}" "${pixels}" "${square_icon}" \
        --out "${staging_app}/AppIcon.iconset/${filename}" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

env \
    CLANG_MODULE_CACHE_PATH="${module_cache_dir}/clang" \
    SWIFT_MODULE_CACHE_PATH="${module_cache_dir}/swift-script" \
    swift "${project_dir}/Scripts/make-icns.swift" \
        "${staging_app}/AppIcon.iconset" \
        "${staging_app}/Contents/Resources/AppIcon.icns" >/dev/null
rm -rf "${staging_app}/AppIcon.iconset"

signing_identity="${LINGGANGU_SIGNING_IDENTITY:--}"
if [[ "${signing_identity}" == "-" ]]; then
    codesign --force --deep --sign - "${staging_app}"
else
    codesign --force --deep --options runtime --timestamp --sign "${signing_identity}" "${staging_app}"
fi
codesign --verify --deep --strict "${staging_app}"
mkdir -p "${install_dir}"
ditto "${staging_app}" "${installed_app}"
touch "${installed_app}"

printf '%s\n' "${installed_app}"
