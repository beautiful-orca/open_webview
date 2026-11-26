#!/system/bin/sh
# External Tools
# Resolve the addon directory once: functions.sh extracts the addon to
# $MODPATH/common/addon/..., not $MODPATH/addon/... (defect 21).
VKS_DIR="$MODPATH/common/addon/Volume-Key-Selector"
chmod -R 0755 "$VKS_DIR/tools"

# Both selectors have three return states: 0 = volume up, 1 = volume down,
# 2 = no answer within $1 seconds. Neither function aborts; the caller decides.
chooseport_legacy() {
    # Keycheck binary by someone755 @Github, idea for code below by Zappo @xda-developers
    [ "$1" ] && local delay=$1 || local delay=60
    local kc="$VKS_DIR/tools/$ARCH32/keycheck"
    [ -x "$kc" ] || return 2
    local start=$(date +%s)
    while true; do
        # Calling it first time detects previous input. Calling it second time will do what we want
        timeout 0 "$kc"
        timeout $delay "$kc"
        local sel=$?
        if [ $sel -eq 42 ]; then
            return 0
        elif [ $sel -eq 41 ]; then
            return 1
        fi
        [ $(( $(date +%s) - start )) -ge $delay ] && return 2
    done
}

chooseport() {
    # Original idea by chainfire and ianmacd @xda-developers
    [ "$1" ] && local delay=$1 || local delay=60
    local start=$(date +%s)
    local last_shown=-1
    while true; do
        # -c 1 is load-bearing: it makes getevent exit, which flushes its
        # block-buffered stdout into the file. Restarting immediately after
        # each exit removes the dead window; timeout 1 bounds each slice so
        # the loop cannot spin when events are flowing.
        timeout 1 /system/bin/getevent -lqc 1 > "$TMPDIR/events" 2>&1
        if grep -q 'KEY_VOLUMEUP *DOWN' "$TMPDIR/events" 2>/dev/null; then
            return 0
        elif grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR/events" 2>/dev/null; then
            return 1
        fi
        # Real deadline, not an iteration count: delay finally means seconds.
        local now=$(date +%s)
        [ $(( now - start )) -ge $delay ] && return 2
        # Visible countdown every 5 s.
        local remaining=$(( delay - (now - start) ))
        if [ $(( remaining % 5 )) -eq 0 ] && [ $remaining -ne $last_shown ]; then
            last_shown=$remaining
            echo "  ${remaining}s"
        fi
    done
}

VKSEL=chooseport
