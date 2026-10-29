#!/usr/bin/env bash
# Put the mirror download table on top of a release's generated notes.
#
# Used by the release job after publishing and by the asset migration workflow,
# so a renamed or relocated mirror never leaves stale links in the release body.
#
# Environment: GH_TOKEN, GITHUB_REPOSITORY, MIRROR_BASE_URL (vars.R2_PUBLIC_BASE_URL),
# TAG (defaults to GITHUB_REF_NAME).
set -euo pipefail

tag="${TAG:-${GITHUB_REF_NAME:?TAG or GITHUB_REF_NAME is required}}"
base="${MIRROR_BASE_URL:-}"
base="${base%/}"
if [ -z "$base" ]; then
	echo "vars.R2_PUBLIC_BASE_URL is not set, skipping mirror links"
	exit 0
fi

gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json body --jq '.body // ""' > generated.md
# Drop the section a previous run (or the migration workflow) left behind, so the
# table is never stacked twice.
python3 - <<'PY'
import pathlib
p = pathlib.Path('generated.md')
body = p.read_text(encoding='utf-8')
while body.lstrip().startswith('## 下载地址'):
	parts = body.split('\n---\n', 1)
	if len(parts) != 2:
		body = ''
		break
	body = parts[1].lstrip('\n')
p.write_text(body, encoding='utf-8')
PY
# GitHub's generated notes end with a compare link to the previous release tag.
# That tag is gone once old releases are removed, so the link would 404: drop the
# line when it points at a tag this repository no longer has.
prev_tag="$(grep -oE '/compare/[^/]+\.\.\.' generated.md | head -1 | sed -E 's|/compare/||; s|\.\.\.$||' || true)"
if [ -n "$prev_tag" ] && ! gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$prev_tag" >/dev/null 2>&1; then
	echo "dropping the compare link: tag $prev_tag no longer exists"
	python3 - <<'PY'
import pathlib, re
p = pathlib.Path('generated.md')
body = p.read_text(encoding='utf-8')
body = re.sub(r'\n*\*\*Full Changelog\*\*: [^\n]*\n?', '\n', body)
p.write_text(body, encoding='utf-8')
PY
fi
sums="picket-code-${tag}-SHA256SUMS"
{
	echo '## 下载地址'
	echo
	echo "镜像（保留最近 3 个版本，国内访问更快）：$base"
	echo
	echo '| 平台 | 下载 |'
	echo '| --- | --- |'
	gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name' |
		grep -E '^picket-code-.*\.(zip|tar\.gz)$' | sort | while read -r asset; do
			label="${asset#picket-code-${tag}-}"
			label="${label%.tar.gz}"
			label="${label%.zip}"
			echo "| $label | $base/$asset |"
		done
	echo "| 校验和 | $base/$sums |"
	echo
	echo '```bash'
	echo "curl -fSL $base/$sums -o SHA256SUMS"
	echo 'sha256sum -c --ignore-missing SHA256SUMS'
	echo '```'
	echo
	echo '---'
	echo
	cat generated.md
} > notes.md
gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --notes-file notes.md
