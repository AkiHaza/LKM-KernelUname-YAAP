#!/system/bin/sh

MODDIR=${0%/*}
if ! sh "$MODDIR/service.sh" --unload; then
	printf '%s\n' 'kernelmask: uninstall could not unload the module; see /data/adb/kernelmask/service.log' >&2
fi
