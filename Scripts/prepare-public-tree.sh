#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:?Provide a NEW output directory for the reviewed public source tree}"
[[ ! -e "${target}" ]] || { echo "Refusing to overwrite an existing directory." >&2; exit 2; }
mkdir -p "${target}/docs/images" "${target}/docs/design/assets" "${target}/Scripts"
for name in Sources Tests Packaging .github; do cp -R "${project_dir}/${name}" "${target}/"; done
for name in .gitignore Package.swift README.md README.en.md LICENSE NOTICE.md THIRD_PARTY_NOTICES.md TRADEMARKS.md COMMERCIAL_USE.md CONTRIBUTING.md SECURITY.md CHANGELOG.md; do
    cp "${project_dir}/${name}" "${target}/${name}"
done
for name in package-local-app.sh make-icns.swift check-api-redirects.py build-beta.sh check-public-tree.py prepare-public-tree.sh; do
    cp "${project_dir}/Scripts/${name}" "${target}/Scripts/${name}"
done
for name in AI_CONFIGURATION_GUIDE.md AI_CONFIGURATION_GUIDE.en.md INVESTMENT_AGENT.md INSTALLATION.md RELEASE_NOTES.md PUBLIC_PLANS.md PUBLIC_SECURITY_REVIEW.md; do
    cp "${project_dir}/docs/${name}" "${target}/docs/${name}"
done
cp "${project_dir}/docs/PUBLIC_PLANS.md" "${target}/PLANS.md"
cp "${project_dir}/docs/PUBLIC_SECURITY_REVIEW.md" "${target}/docs/API_SECURITY_REVIEW.md"
cp "${project_dir}/docs/images/workbench.png" "${target}/docs/images/workbench.png"
cp "${project_dir}/docs/design/assets/linggangu-mushroom-base.png" "${target}/docs/design/assets/"
python3 "${target}/Scripts/check-public-tree.py" "${target}"
echo "Prepared public source tree (no Git credentials, no remote): ${target}"
