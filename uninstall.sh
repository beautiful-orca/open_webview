#!/system/bin/sh
# Idempotent: every step is safe to run twice and on a device that never had
# the module installed.

# The package this module installed, recorded in .webview at install time.
VW_PACKAGE=$(sed -n 's/^VW_PACKAGE=//p' "$MODPATH/.webview" 2>/dev/null | head -n1)

# The WebView cleanup runs in a background subshell after boot completes:
# pm path needs PackageManager up, and system_server owns overlays.xml.
(
  # Wait for boot to complete. resetprop -w sys.boot_completed 1 waits until
  # the property becomes 1; waiting on 0 returns immediately because the
  # property is unset during boot (§14.7).
  resetprop -w sys.boot_completed 1 2>/dev/null

  # Remove the /data/app update the update button (action.sh) may have
  # installed. No --user flag: without it pm defaults to USER_ALL, which
  # removes the update and restores the system copy; --user 0 would instead
  # set DELETE_SYSTEM_APP and merely disable the package for that user. Without
  # this, Cromite's data app keeps overriding the stock WebView this module
  # restores, and Vanadium's becomes dead weight once the overlay is gone.
  [ -n "$VW_PACKAGE" ] && pm uninstall "$VW_PACKAGE" >/dev/null 2>&1

  # Remove the /data/app updates and data dirs of the providers this module
  # can install. pm path is authoritative — the old find with a leading-dot
  # pattern ("*.com.android.webview*") never matched a real path (§2.8 #15).
  for pkg in com.android.webview app.vanadium.webview; do
    pm path "$pkg" 2>/dev/null | sed -n 's/^package://p' | while read -r apk; do
      case $apk in
      /data/app/*) rm -rf "$(dirname "$apk")" 2>/dev/null ;;
      esac
    done
    rm -rf "/data/data/$pkg" 2>/dev/null
  done

  # Best-effort: remove the stale overlay entry the old post-fs-data.sh wrote.
  # Harmless if system_server rewrites the file first — the overlay APK is
  # gone with the module, so the entry points nowhere.
  if [ -f /data/system/overlays.xml ]; then
    sed -i 's|<item packageName="app.vanadium.WebviewOverlay"[^>]*/>||' /data/system/overlays.xml
  fi
) &

# Don't modify anything after this
if [ -f $INFO ]; then
  while read LINE; do
    if [ "$(echo -n $LINE | tail -c 1)" == "~" ]; then
      continue
    elif [ -f "$LINE~" ]; then
      mv -f $LINE~ $LINE
    else
      rm -f $LINE
      while true; do
        LINE=$(dirname $LINE)
        [ "$(ls -A $LINE 2>/dev/null)" ] && break 1 || rm -rf $LINE
      done
    fi
  done < $INFO
  rm -f $INFO
fi
