#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_DIR=/data/adb/kernelmask
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_FILE="$CONFIG_DIR/service.log"
KO_PATH="$MODDIR/kernelmask.ko"
LOCK_DIR="$CONFIG_DIR/.lock"
LOCK_HELD=0

log_msg() {
	mkdir -p "$CONFIG_DIR" 2>/dev/null || true
	printf '%s kernelmask: %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

release_lock() {
	if [ "$LOCK_HELD" -eq 1 ]; then
		rm -f "$LOCK_DIR/pid" "$LOCK_DIR/time" 2>/dev/null || true
		rmdir "$LOCK_DIR" 2>/dev/null || true
		LOCK_HELD=0
	fi
}
trap 'release_lock' 0
trap 'release_lock; exit 129' HUP
trap 'release_lock; exit 130' INT
trap 'release_lock; exit 143' TERM

acquire_lock() {
	[ "$LOCK_HELD" -eq 1 ] && return 0
	mkdir -p "$CONFIG_DIR" 2>/dev/null || return 1
	start=$(date +%s 2>/dev/null || printf 0)
	while ! mkdir "$LOCK_DIR" 2>/dev/null; do
		pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
		stamp=$(cat "$LOCK_DIR/time" 2>/dev/null || true)
		now=$(date +%s 2>/dev/null || printf 0)
		stale=0
		case "$pid" in
			''|*[!0-9]*) [ "$stamp" -gt 0 ] 2>/dev/null && [ "$now" -ge "$stamp" ] 2>/dev/null && [ $((now - stamp)) -ge 30 ] 2>/dev/null && stale=1 ;;
			*) kill -0 "$pid" 2>/dev/null || stale=1 ;;
		esac
		case "$pid" in
			''|*[!0-9]*)
				[ "$now" -ge "$start" ] 2>/dev/null && [ $((now - start)) -ge 30 ] 2>/dev/null && stale=1
				;;
		esac
		if [ "$stale" -eq 1 ]; then
			stale_dir="$LOCK_DIR.stale.$$.${now}"
			if mv "$LOCK_DIR" "$stale_dir" 2>/dev/null; then
				rm -f "$stale_dir/pid" "$stale_dir/time" 2>/dev/null || true
				rmdir "$stale_dir" 2>/dev/null || true
				continue
			fi
		fi
		sleep 1
	done
	printf '%s\n' "$$" > "$LOCK_DIR/pid"
	printf '%s\n' "$(date +%s 2>/dev/null || printf 0)" > "$LOCK_DIR/time"
	LOCK_HELD=1
}

run_locked() {
	acquire_lock || return 1
	"$@"
	result=$?
	release_lock
	return "$result"
}

valid_value() {
	value=$1
	value_length=$(printf '%s' "$value" | wc -c)
	[ "$value_length" -le 64 ] || return 1
	invalid=$(printf '%s' "$value" | LC_ALL=C tr -d ' -~' | wc -c)
	[ "$invalid" -eq 0 ] || return 1
	case "$value" in *\"*|*\'*|*\\*) return 1 ;; esac
	return 0
}

reset_values() {
	enabled=0
	sysname=
	nodename=
	release=
	version=
	machine=
	domainname=
}

read_config() {
	reset_values
	error=
	seen_enabled=0
	seen_sysname=0
	seen_nodename=0
	seen_release=0
	seen_version=0
	seen_machine=0
	seen_domainname=0
	[ -e "$1" ] || return 0
	[ -f "$1" ] || { error='configuration is not a regular file'; return 1; }
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] || continue
		case "$line" in \#*) continue ;; esac
		case "$line" in *=*) ;; *) error='line has no ='; return 1 ;; esac
		key=${line%%=*}
		value=${line#*=}
		case "$key" in
			enabled)
				[ "$seen_enabled" -eq 0 ] || { error='duplicate enabled'; return 1; }
				seen_enabled=1
				case "$value" in 0|1|y|Y|true|TRUE) enabled=$value ;; *) error='invalid enabled value'; return 1 ;; esac
				;;
			sysname|nodename|release|version|machine|domainname)
				case "$key" in
					sysname) seen=$seen_sysname ;;
					nodename) seen=$seen_nodename ;;
					release) seen=$seen_release ;;
					version) seen=$seen_version ;;
					machine) seen=$seen_machine ;;
					domainname) seen=$seen_domainname ;;
				esac
				[ "$seen" -eq 0 ] || { error="duplicate $key"; return 1; }
				case "$key" in
					sysname) seen_sysname=1; sysname=$value ;;
					nodename) seen_nodename=1; nodename=$value ;;
					release) seen_release=1; release=$value ;;
					version) seen_version=1; version=$value ;;
					machine) seen_machine=1; machine=$value ;;
					domainname) seen_domainname=1; domainname=$value ;;
				esac
				valid_value "$value" || { error="invalid $key value"; return 1; }
				;;
			*) error="unknown key $key"; return 1 ;;
		esac
	done < "$1"
	case "$enabled" in 1|y|Y|true|TRUE) enabled=1 ;; *) enabled=0 ;; esac
}

ensure_config() {
	if [ ! -e "$CONFIG_FILE" ]; then
		printf '%s\n' 'enabled=0' 'sysname=' 'nodename=' 'release=' 'version=' 'machine=' 'domainname=' > "$CONFIG_FILE" || return 1
		chmod 0600 "$CONFIG_FILE" 2>/dev/null || true
	fi
}

loaded() { grep -q '^kernelmask ' /proc/modules 2>/dev/null; }

unload_locked() {
	loaded || { log_msg 'already unloaded'; return 0; }
	out="$CONFIG_DIR/.rmmod.$$"
	if ! rmmod kernelmask >"$out" 2>&1; then
		msg=$(cat "$out" 2>/dev/null || printf 'no diagnostic output')
		rm -f "$out"
		log_msg "rmmod failed: $msg"
		printf 'kernelmask: rmmod failed: %s\n' "$msg" >&2
		return 1
	fi
	rm -f "$out"
	loaded && { log_msg 'rmmod reported success but module remains loaded'; printf '%s\n' 'kernelmask: rmmod reported success but module remains loaded' >&2; return 1; }
	log_msg 'unloaded'
}

load_locked() {
	reload=$1
	read_config "$CONFIG_FILE" || { log_msg "invalid configuration: $error"; printf 'kernelmask: invalid configuration: %s\n' "$error" >&2; return 1; }
	if loaded; then
		[ "$reload" -eq 0 ] && { log_msg 'already loaded'; return 0; }
		unload_locked || return 1
	fi
	[ "$enabled" -eq 1 ] || { log_msg 'disabled'; return 0; }
	[ -r "$KO_PATH" ] || { log_msg "missing module: $KO_PATH"; printf 'kernelmask: missing module: %s\n' "$KO_PATH" >&2; return 1; }
	out="$CONFIG_DIR/.insmod.$$"
	if ! insmod "$KO_PATH" \
		enabled="$enabled" \
		sysname="\"$sysname\"" \
		nodename="\"$nodename\"" \
		release="\"$release\"" \
		version="\"$version\"" \
		machine="\"$machine\"" \
		domainname="\"$domainname\"" >"$out" 2>&1; then
		msg=$(cat "$out" 2>/dev/null || printf 'no diagnostic output')
		rm -f "$out"
		log_msg "insmod failed: $msg"
		printf 'kernelmask: insmod failed: %s\n' "$msg" >&2
		return 1
	fi
	rm -f "$out"
	loaded || { log_msg 'insmod reported success but module is not loaded'; printf '%s\n' 'kernelmask: insmod reported success but module is not loaded' >&2; return 1; }
	log_msg "loaded enabled=$enabled release=$release version=$version"
}

reload_locked() {
	ensure_config && load_locked "$1"
}

print_config() {
	read_config "$CONFIG_FILE" || { printf 'kernelmask: invalid configuration: %s\n' "$error" >&2; return 1; }
	printf 'enabled=%s\nsysname=%s\nnodename=%s\nrelease=%s\nversion=%s\nmachine=%s\ndomainname=%s\n' "$enabled" "$sysname" "$nodename" "$release" "$version" "$machine" "$domainname"
}

save_config() {
	tmp="$CONFIG_FILE.tmp.$$"
	backup="$CONFIG_FILE.bak.$$"
	had=0
	if [ -f "$CONFIG_FILE" ]; then
		had=1
		cp "$CONFIG_FILE" "$backup" || { printf '%s\n' 'kernelmask: cannot back up existing configuration' >&2; return 1; }
	fi
	cat > "$tmp" || { rm -f "$tmp" "$backup"; printf '%s\n' 'kernelmask: cannot write temporary configuration' >&2; return 1; }
	chmod 0600 "$tmp" 2>/dev/null || true
	read_config "$tmp" || { rm -f "$tmp" "$backup"; log_msg "rejected configuration: $error"; printf 'kernelmask: rejected configuration: %s\n' "$error" >&2; return 1; }
	old=0
	loaded && old=1
	mv "$tmp" "$CONFIG_FILE" || { rm -f "$tmp" "$backup"; printf '%s\n' 'kernelmask: cannot install new configuration' >&2; return 1; }
	if load_locked 1; then
		rm -f "$backup"
		log_msg 'configuration saved and module reloaded'
		return 0
	fi
	log_msg 'new configuration failed; restoring previous configuration'
	if [ "$had" -eq 1 ]; then
		mv "$backup" "$CONFIG_FILE" || { printf '%s\n' 'kernelmask: reload failed and configuration rollback failed' >&2; return 1; }
	else
		rm -f "$CONFIG_FILE"
	fi
	if [ "$old" -eq 1 ]; then
		load_locked 1 || { printf '%s\n' 'kernelmask: reload failed; file restored but previous module reload failed' >&2; return 1; }
	elif loaded; then
		unload_locked || { printf '%s\n' 'kernelmask: reload failed; file restored but module cleanup failed' >&2; return 1; }
	fi
	printf '%s\n' 'kernelmask: reload failed; previous configuration restored' >&2
	return 1
}

mkdir -p "$CONFIG_DIR" 2>/dev/null || { printf 'kernelmask: cannot create %s\n' "$CONFIG_DIR" >&2; exit 1; }
case "$1" in
	--reload) run_locked reload_locked 1; exit $? ;;
	--unload) run_locked unload_locked; exit $? ;;
	--save-config) run_locked save_config; exit $? ;;
	--read-config) acquire_lock || exit 1; ensure_config && print_config; result=$?; release_lock; exit "$result" ;;
	'') acquire_lock || exit 1; ensure_config && load_locked 0; result=$?; release_lock; exit "$result" ;;
	*) printf 'kernelmask: unknown option: %s\n' "$1" >&2; exit 2 ;;
esac
