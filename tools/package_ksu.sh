#!/usr/bin/env sh
set -eu

KO_PATH=${1:-kernel/kernelmask.ko}
OUTPUT=${2:-out/yaap-kernelmask-ksu.zip}
SCRIPT_DIR=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(unset CDPATH; cd -- "$SCRIPT_DIR/.." && pwd)
TEMPLATE_DIR="$REPO_ROOT/ksu-module"

case "$KO_PATH" in
	/*) ;;
	*) KO_PATH="$REPO_ROOT/$KO_PATH" ;;
esac
case "$OUTPUT" in
	/*) ;;
	*) OUTPUT="$REPO_ROOT/$OUTPUT" ;;
esac

[ -s "$KO_PATH" ] || { echo "Missing kernel module: $KO_PATH" >&2; exit 1; }
[ -d "$TEMPLATE_DIR/webroot" ] || { echo "Missing WebUI template" >&2; exit 1; }

mkdir -p "$REPO_ROOT/out" "$(dirname -- "$OUTPUT")"
STAGE_DIR=$(mktemp -d "$REPO_ROOT/out/ksu-stage.XXXXXX")
case "$STAGE_DIR" in
	"$REPO_ROOT"/out/ksu-stage.*) ;;
	*) echo "Invalid staging directory: $STAGE_DIR" >&2; exit 1 ;;
esac
trap 'rm -rf "$STAGE_DIR"' EXIT
cp "$TEMPLATE_DIR/module.prop" "$TEMPLATE_DIR/service.sh" \
	"$TEMPLATE_DIR/post-fs-data.sh" "$TEMPLATE_DIR/uninstall.sh" "$STAGE_DIR/"
cp -R "$TEMPLATE_DIR/webroot" "$STAGE_DIR/webroot"
cp "$KO_PATH" "$STAGE_DIR/kernelmask.ko"
chmod 0755 "$STAGE_DIR/service.sh" "$STAGE_DIR/post-fs-data.sh" \
	"$STAGE_DIR/uninstall.sh"

rm -f "$OUTPUT"
if command -v zip >/dev/null 2>&1; then
	(cd "$STAGE_DIR" && zip -q -r "$OUTPUT" .)
elif command -v python3 >/dev/null 2>&1; then
	(cd "$STAGE_DIR" && python3 -m zipfile -c "$OUTPUT" .)
else
	echo "Missing dependency: zip or python3" >&2
	exit 1
fi

echo "Created KernelSU package: $OUTPUT"
