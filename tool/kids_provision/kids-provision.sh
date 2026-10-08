#!/system/bin/sh
# kids-provision.sh — keep Hearth's OWN apps in Google TV kids profiles, with a one-press clean undo.
#
# WHAT THIS IS
#   The exact shell steps Hearth runs — as the `shell` user, over its own loopback adb connection
#   (see README: "Hearth as its own adb host") — to add or remove ITS OWN apps (Hearth, HearthTube)
#   in each kid profile. Google TV's launcher uninstalls any non-approved app from a kids profile at
#   every profile start; the per-user "block uninstall" flag set here is what keeps these two apps.
#   This is a reviewable prototype of that logic; the Hearth app would run these same steps.
#
# USER CONTROL — nothing here is automatic or hidden:
#   * Hearth runs `add` ONLY when the parent presses
#       Settings -> Setup & permissions -> "Add Hearth to kids' profiles".
#     Hearth runs `remove` ONLY from the matching "Remove Hearth from kids' profiles".
#   * It touches ONLY Hearth's own packages (HEARTH, HEARTHTUBE below) — never any other app.
#   * `state` only reports; it changes nothing.
#   * The one-time "Allow debugging?" prompt the parent approves on screen (see README) is the consent
#     gate for ALL of this. Without that approval none of these commands can run.
#
# SAFETY — THE ORPHAN TRAP (proven on-device, 2026-10-08):
#   A block-uninstall-protected copy cannot be removed until the flag is lifted — a shell uninstall of
#   a protected package returns `Failure [DELETE_FAILED_OWNER_BLOCKED]` and removes nothing. So if Hearth
#   is uninstalled from the TV while these flags are set, Android leaves the protected copies behind in
#   the kids' profiles, invisible and hard to clear without a computer. THEREFORE:
#     * `remove` ALWAYS lifts the flag BEFORE it uninstalls (see remove_user()).
#     * Hearth's Settings must run `remove` BEFORE the parent uninstalls Hearth itself, and must say so.
#     * README lists the manual adb commands to undo by hand if Hearth is already gone.
#
# WHY BLOCK-UNINSTALL AND NOT DEVICE ADMIN:
#   The block-uninstall flag is fully reversible from the `shell` user (set AND lift). An active device
#   admin is NOT: `dpm remove-active-admin` throws SecurityException for a non-test admin, so a device
#   admin set by an app that is later uninstalled is stuck (short of factory reset). Using the flag for
#   both apps keeps add AND remove a clean, no-computer round trip.
#
# Usage:  sh kids-provision.sh state
#         sh kids-provision.sh add    [userId ...]
#         sh kids-provision.sh remove [userId ...]
#   With no user ids it auto-detects profile users (every user but the owner, 0). The real Hearth
#   integration passes the kid user ids it already tracks (ProfileUsers) instead of auto-detecting.

set -u

# --- Hearth's own packages: the ONLY packages this script ever touches. ---
HEARTH=com.leanbitlab.ltvL
HEARTHTUBE=com.thesiegs.hearthtube
PKGS="$HEARTH $HEARTHTUBE"

# tool/block_uninstall compiled to a dex that Hearth places here. It sets the per-user block-uninstall
# flag via IPackageManager (no `pm` verb exposes it). See tool/block_uninstall/README.md.
DEX=/data/local/tmp/block-uninstall.dex

# Set/read the per-user block-uninstall flag.  blockflag <pkg> <user> [true|false]
blockflag() {
  CLASSPATH="$DEX" app_process /system/bin BlockUninstall "$@"
}

# Profile users = every user but the owner (0). Hearth passes its tracked kid ids instead.
kid_users() {
  pm list users | sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p' | grep -v '^0$'
}

# Is <pkg> currently launchable in <user>?  installed_in <pkg> <user>
installed_in() {
  pm list packages --user "$2" 2>/dev/null | grep -x "package:$1"
}

# Report only — changes nothing. Backs the Settings "which profiles have Hearth/HearthTube" view.
state() {
  for u in $(kid_users); do
    echo "profile user $u:"
    for p in $PKGS; do
      if installed_in "$p" "$u" >/dev/null 2>&1; then inst=installed; else inst="not installed"; fi
      flag=$(blockflag "$p" "$u" 2>/dev/null | sed -n 's/.*blockUninstall=//p')
      echo "    $p: $inst, blockUninstall=${flag:-?}"
    done
  done
}

# INSTALL step — USER-CONTROLLED (only from "Add Hearth to kids' profiles").
add_user() {
  u=$1
  for p in $PKGS; do
    # 1) INSTALLED here: make the owner's copy launchable in this profile. The APK is device-wide,
    #    so install-existing just flips the per-user bit (instant, no download). This is the step that
    #    sends the parent one Family Link "app added" notification, once per app per profile.
    pm install-existing --user "$u" "$p" >/dev/null 2>&1
    # 2) PROTECTED here: keep the launcher from uninstalling it at the next profile start.
    blockflag "$p" "$u" true >/dev/null 2>&1
    echo "  user $u: added + protected $p"
  done
}

# UNINSTALL step — USER-CONTROLLED (only from "Remove Hearth from kids' profiles").
remove_user() {
  u=$1
  for p in $PKGS; do
    # ORPHAN-TRAP SAFETY: lift the flag FIRST. If we uninstalled while protected the uninstall would be
    # refused (DELETE_FAILED_OWNER_BLOCKED) and the copy would be orphaned.
    blockflag "$p" "$u" false >/dev/null 2>&1
    # UNINSTALLED here: remove this profile's copy (the device-wide APK in user 0 is untouched).
    pm uninstall --user "$u" "$p" >/dev/null 2>&1
    echo "  user $u: unprotected + removed $p"
  done
  # If a build ever used device admin to protect Hearth, REMOVE cannot clear it from shell (non-test
  # admin). Hearth must call DevicePolicyManager.removeActiveAdmin() on ITSELF from its agent in that
  # profile. This script avoids that by protecting both apps with the reversible flag only.
}

cmd=${1:-state}
[ $# -gt 0 ] && shift
users="$*"
[ -n "$users" ] || users=$(kid_users)

case "$cmd" in
  state)  state ;;
  add)    echo "Adding Hearth's apps to profiles: $users"; for u in $users; do add_user "$u"; done; echo "current state:"; state ;;
  remove) echo "Removing Hearth's apps from profiles: $users"; for u in $users; do remove_user "$u"; done; echo "current state:"; state ;;
  *) echo "usage: sh kids-provision.sh {state|add|remove} [userId ...]"; exit 2 ;;
esac
