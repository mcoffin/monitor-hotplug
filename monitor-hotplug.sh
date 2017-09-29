#!/bin/bash

set -x

if [ -z "$1" ]; then
	echo "You must specify a device name!" >&2
	exit 1
fi
device="$1"

xrandr_monitor_name() {
	local monitor=$(basename $1)
	local card_dir=$(dirname $1)
	local prefix="$device-"
	local monitor_base=$(echo -n "$monitor" | sed -E 's/-[0-9]+$//')
	# First, remove the `cardN-` prefix
	monitor=${monitor#$prefix}
	monitor=$(echo "$monitor" | awk 'match($0, /^(.*)-([0-9]+)$/, cap) {sep="-"; newidx=cap[2] - 1; name=cap[1] sep newidx; print name}')
	local monitor_count=$(xrandr | (egrep "^$monitor" || echo -n '') | wc -l)
	if [ "$monitor_count" -ne "1" ]; then
		monitor=$(xrandr | egrep "^${monitor_base#$prefix}" | awk '{print $1}')
		if [ "$(echo $monitor | wc -l)" -gt 1 -o -z "$monitor" ]; then
			echo "Couldn't find xrandr monitor name for monitor: $1" >&2
			return 1
		fi
	fi
	echo -n $monitor
}

set_mode() {
	if [ ! -z "$DISPLAY" ]; then
		if xset q &>/dev/null; then
			mode=x11
			return 0
		else
			echo "No X server at \$DISPLAY [$DISPLAY]" >&2
		fi
	fi
	return 1
}

enable_monitor() {
	case $mode in
		x11)
			local monitor=$(xrandr_monitor_name $1 || return $?)
			xrandr --output $monitor --auto || return $?
			;;
		*)
			echo "Can't enable moitor with mode: $mode"
			return 1
			;;
	esac
}

disable_monitor() {
	case $mode in
		x11)
			local monitor=$(xrandr_monitor_name $1 || return $?)
			xrandr --output "$monitor" --off || return $?
			;;
		*)
			echo "Can't disable monitor in mode: $mode" >&2
			return 1
			;;
	esac
}

change_monitors() {
	declare -a connected_monitors
	for m in $(find -H "/sys/class/drm/$1" -mindepth 1 -maxdepth 1 -name "$1-*" || return 1); do
		if [ "$(cat $m/status)" == "connected" ]; then
			connected_monitors+=("$m")
		fi
	done
	echo "connected_monitors: ${connected_monitors[@]}"
	if [ ${#connected_monitors[@]} -lt 2 ]; then
		# We have less than 2 monitors connected, so lets just enable the ones that are connected
		for m in ${connected_monitors[@]}; do
			local name=$(basename $m)
			enable_monitor $name
		done
		return 0
	fi
	declare -a enabled_monitors
	declare -a disabled_monitors
	for m in ${connected_monitors[@]}; do
		if [ "$(cat $m/enabled)" == "enabled" ]; then
			enabled_monitors+=("$m")
		else
			disabled_monitors+=("$m")
		fi
	done
	if [ ${#enabled_monitors[@]} -eq 1 -a ${#disabled_monitors[@]} -eq 1 ]; then
		for m in ${disabled_monitors[@]}; do
			enable_monitor "$m" || return 1
		done
		for m in ${enabled_monitors[@]}; do
			disable_monitor "$m" || return 1
		done
	fi
}

set_mode || exit 1
change_monitors $1 || exit 1
