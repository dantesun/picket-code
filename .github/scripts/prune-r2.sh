#!/usr/bin/env bash
# Keep only the newest published versions in the R2 mirror.
#
# Objects look like `picket-code-<tag>-<platform>-<arch>.<ext>` and
# `picket-code-<tag>-SHA256SUMS`. Anything else in the bucket (screenshots and
# other assets) is left untouched: only keys matching the versioned release
# pattern are ever deleted.
#
# Environment:
#   REMOTE         rclone remote path         (default r2:picket-releases/)
#   KEEP           versions to keep           (default 3)
#   PRUNE_DRY_RUN  set to 1 to only report    (default 0)
set -euo pipefail

REMOTE="${REMOTE:-r2:picket-releases/}"
KEEP="${KEEP:-3}"
DRY_RUN="${PRUNE_DRY_RUN:-0}"

# `v1.143.1`, `v1.143.1-p2`, ...: anything else is skipped on purpose so a
# malformed tag can never make the script delete the wrong objects.
version_re='^picket-code-(v[0-9]+\.[0-9]+\.[0-9]+(-p[0-9]+)?)-'

objects="$(rclone lsf "$REMOTE" | grep -E "$version_re" || true)"
if [ -z "$objects" ]; then
	echo "no versioned objects under $REMOTE; nothing to prune"
	exit 0
fi

# Order by base version first, then by the -pN suffix (a plain v1.143.1 sorts
# before v1.143.1-p1, which is what we want).
versions="$(printf '%s\n' "$objects" \
	| sed -E 's/^picket-code-(v[0-9]+\.[0-9]+\.[0-9]+(-p[0-9]+)?)-.*/\1/' \
	| sort -u \
	| awk '{
		if (match($0, /-p[0-9]+$/)) { suffix = substr($0, RSTART + 2); base = substr($0, 1, RSTART - 1) }
		else { suffix = 0; base = $0 }
		printf "%s %s %s\n", base, suffix, $0
	}' \
	| sort -k1,1V -k2,2n \
	| awk '{ print $3 }')"

total="$(printf '%s\n' "$versions" | wc -l | tr -d ' ')"
echo "found $total version(s), keeping the newest $KEEP"
printf '  %s\n' $versions

if [ "$total" -le "$KEEP" ]; then
	echo "nothing to prune"
	exit 0
fi

drop="$(printf '%s\n' "$versions" | head -n $((total - KEEP)))"

while read -r version; do
	[ -n "$version" ] || continue
	pattern="^picket-code-$(printf '%s' "$version" | sed 's/\./\\./g')-"
	printf '%s\n' "$objects" | grep -E "$pattern" | while read -r object; do
		[ -n "$object" ] || continue
		if [ "$DRY_RUN" = "1" ]; then
			echo "DRY-RUN delete $REMOTE$object"
		else
			echo "delete $REMOTE$object"
			rclone deletefile "$REMOTE$object"
		fi
	done
done <<< "$drop"

echo "prune finished"
