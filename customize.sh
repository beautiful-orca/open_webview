#!/system/bin/sh
##########################################################################################
# Config Flags
##########################################################################################

# Uncomment and change 'MINAPI' and 'MAXAPI' to the minimum and maximum android version for your mod
# Uncomment DYNLIB if you want libs installed to vendor for oreo+ and system for anything older
# Uncomment DEBUG if you want full debug logs (saved to /sdcard)
MINAPI=29
#MAXAPI=25
#DYNLIB=true
#DEBUG=true

##########################################################################################
# Replace list
##########################################################################################

# List all directories you want to directly replace in the system
# Check the documentations for more info why you would need this

# Construct your list in the following format
# This is an example
REPLACE_EXAMPLE="
/system/app/Youtube
/system/priv-app/SystemUI
/system/priv-app/Settings
/system/framework
"

# Construct your own list here
REPLACE="
"

##########################################################################################
# Permissions
##########################################################################################

set_permissions() {
  # bin/curl is the update button's curl (action.sh); set_perm_recursive in
  # functions.sh leaves it at 0644.
  set_perm $MODPATH/bin/curl 0 0 0755

  # Note that all files/folders in magisk module directory have the $MODPATH prefix - keep this prefix on all of your files/folders
  # Some examples:
  
  # For directories (includes files in them):
  # set_perm_recursive  <dirname>                <owner> <group> <dirpermission> <filepermission> <contexts> (default: u:object_r:system_file:s0)
  
  # set_perm_recursive $MODPATH/system/lib 0 0 0755 0644
  # set_perm_recursive $MODPATH/system/vendor/lib/soundfx 0 0 0755 0644

  # For files (not in directories taken care of above)
  # set_perm  <filename>                         <owner> <group> <permission> <contexts> (default: u:object_r:system_file:s0)
  
  # set_perm $MODPATH/system/lib/libart.so 0 0 0644
  # set_perm /data/local/tmp/file.txt 0 0 644
}

SKIPUNZIP=1
unzip -qjo "$ZIPFILE" 'common/functions.sh' -d $TMPDIR >&2
# Magisk and KernelSU both report ARCH=x64 for an x86_64 device (util_functions.sh,
# api_level_arch_detect), while the tools directory and the provider registry use the
# ABI name. Normalise once, here, before anything reads $ARCH.
[ "$ARCH" = "x64" ] && ARCH=x86_64

# Detect a previous install before anything is extracted: while an upgrade
# runs, $MODPATH is the modules_update copy and the old module is still in
# modules/. Read-only; nothing on the device changes yet.
IS_UPGRADE=0
[ -f $NVBASE/modules/$MODID/module.prop ] && IS_UPGRADE=1

# One-shot migration from the previous module generation (PROJECT-NOTES §9.3).
# Every step the old post-fs-data.sh ran at boot lands here, once, at install
# time. Called at the very end of this script: clean_up 1 aborts the shell, so
# the migration only runs after the download and overlay copy succeeded — a
# failed upgrade is a no-op and leaves the old module fully working.
migrate_previous_install() {
  local old_dir=$NVBASE/modules/$MODID
  # The old post-fs-data.sh must not survive the upgrade even if Magisk's
  # module swap would remove it anyway: a surviving copy would keep editing
  # overlays.xml at every boot.
  rm -f "$old_dir/post-fs-data.sh"
  # Remove the stale app.vanadium.WebviewOverlay entry the old boot script
  # wrote — targeted on the exact packageName (the old com*webview pattern
  # never matched anything). Best-effort: system_server owns overlays.xml and
  # may rewrite it. A static RRO in a partition overlay dir is enabled at boot
  # without any entry, so nothing is re-added.
  if [ -f /data/system/overlays.xml ]; then
    sed -i 's|<item packageName="app.vanadium.WebviewOverlay"[^>]*/>||' /data/system/overlays.xml
  fi
  # Drop the compiled idmap of the old overlay; if the glob matches nothing,
  # nothing is lost.
  rm -f /data/resource-cache/*WebviewOverlay.apk@idmap
  # The new Vanadium does not need the Trichrome library APKs.
  pm uninstall app.vanadium.trichromelibrary >/dev/null 2>&1
  pm uninstall com.google.android.trichromelibrary >/dev/null 2>&1
  # A stale backup of packages.xml & co must never be restorable.
  rm -rf "$old_dir/backup"
}

. $TMPDIR/functions.sh

OVERLAY_IMAGE_EXTRA=0     # number of kb need to be added to overlay.img
OVERLAY_IMAGE_SHRINK=true # shrink overlay.img or not?

if [ -f "/data/adb/modules/magisk_overlayfs/util_functions.sh" ] && \
    /data/adb/modules/magisk_overlayfs/overlayfs_system --test; then
  ui_print "- Add support for overlayfs"
  . /data/adb/modules/magisk_overlayfs/util_functions.sh
  support_overlayfs && rm -rf "$MODPATH"/system
fi

# Runs late, only when the install above succeeded (a failed download aborts
# the shell before this line).
if [[ $IS_UPGRADE -eq 1 ]]; then
  migrate_previous_install
fi
