# block_uninstall

Sets Android's per-user "block uninstall" flag on Hearth or HearthTube in a kids profile user, so Google TV's
launcher can't remove them at profile start, without making them device admins. Why this should work and what's
still untested: [docs/kids-profile-installs.md](../../docs/kids-profile-installs.md).

## Build (once, on the computer)

Needs a JDK and the Android SDK's `d8` (in `build-tools/<version>/`).

```powershell
cd tool\block_uninstall
javac --release 8 -d build BlockUninstall.java
& "$env:LOCALAPPDATA\Android\sdk\build-tools\<version>\d8.bat" --min-api 26 --output build build\BlockUninstall.class
adb push build\classes.dex /data/local/tmp/block-uninstall.dex
```

## Use

```powershell
adb shell pm list users                       # kids: 10, 11, 12 on the test TV
adb shell pm install-existing --user 10 com.thesiegs.hearthtube   # once; Family Link notifies once
adb shell CLASSPATH=/data/local/tmp/block-uninstall.dex app_process /system/bin BlockUninstall com.thesiegs.hearthtube 10 true
adb shell CLASSPATH=/data/local/tmp/block-uninstall.dex app_process /system/bin BlockUninstall com.thesiegs.hearthtube 10
```

The last line only reads the flag back (`blockUninstall=true`). Then switch to that kid's profile and watch Google
TV try and fail:

```powershell
adb logcat -v threadtime | Select-String -Pattern "b/427107950|TvProfileHelper|TvSystemBackend|DELETE_FAILED|blocked by admin"
```

Undo: the same command with `false`. Uninstalling Hearth or HearthTube from the owner's profile leaves the copies in
users where uninstall is blocked, so unblock those first.
