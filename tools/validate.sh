#!/usr/bin/env bash
set -euo pipefail

KO_PATH=${1:-kernel/kernelmask.ko}
KERNEL_RELEASE=${2:-}

command -v llvm-readelf >/dev/null || { echo "llvm-readelf is required" >&2; exit 1; }
command -v modinfo >/dev/null || { echo "modinfo is required" >&2; exit 1; }
test -s "$KO_PATH"

machine=$(llvm-readelf -h "$KO_PATH" | awk -F: '/Machine:/ {gsub(/^[[:space:]]+/, "", $2); print $2}')
test "$machine" = AArch64

vermagic=$(modinfo -F vermagic "$KO_PATH")
if [ -n "$KERNEL_RELEASE" ]; then
	case "$vermagic" in
		"$KERNEL_RELEASE "*) ;;
		*) echo "vermagic mismatch: $vermagic (kernel $KERNEL_RELEASE)" >&2; exit 1 ;;
	esac
fi
case " $vermagic " in
	*" modversions "*) ;;
	*) echo "module lacks modversions: $vermagic" >&2; exit 1 ;;
esac

versions_size=$(llvm-readelf -SW "$KO_PATH" | awk '
	{ for (i = 1; i <= NF; i++) {
		if ($i == "__versions") { print $(i + 4); exit }
	} }
')
case "$versions_size" in
	''|*[!0-9A-Fa-f]*) echo "invalid __versions size: $versions_size" >&2; exit 1 ;;
	*[!0]*) ;;
	*) echo "empty __versions" >&2; exit 1 ;;
esac

printf 'valid: %s (%s, __versions=%s)\n' "$KO_PATH" "$vermagic" "$versions_size"
