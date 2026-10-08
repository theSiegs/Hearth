/**
 * Sets or reads Android's per-user "block uninstall" flag for a package, run as adb's shell user (which holds
 * DELETE_PACKAGES, all that IPackageManager.setBlockUninstallForUser asks for). No pm command exposes it.
 *
 * Usage (see README.md for building the dex):
 *   adb shell CLASSPATH=/data/local/tmp/block-uninstall.dex app_process /system/bin BlockUninstall <package> <user> [true|false]
 * Without true/false it only prints the current state.
 */
public class BlockUninstall {
    public static void main(String[] args) throws Exception {
        if (args.length < 2 || args.length > 3) {
            System.err.println("usage: BlockUninstall <package> <user> [true|false]");
            System.exit(2);
        }
        String pkg = args[0];
        int user = Integer.parseInt(args[1]);

        // Reflection only, so this builds with a plain JDK (no hidden-API android.jar)
        Object binder = Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "package");
        Object pm = Class.forName("android.content.pm.IPackageManager$Stub")
                .getMethod("asInterface", Class.forName("android.os.IBinder")).invoke(null, binder);
        Class<?> ipm = Class.forName("android.content.pm.IPackageManager");

        if (args.length == 3) {
            if (!args[2].equals("true") && !args[2].equals("false")) {
                System.err.println("third argument must be true or false");
                System.exit(2);
            }
            Object ok = ipm.getMethod("setBlockUninstallForUser", String.class, boolean.class, int.class)
                    .invoke(pm, pkg, Boolean.parseBoolean(args[2]), user);
            System.out.println("setBlockUninstallForUser returned " + ok);
        }
        Object blocked = ipm.getMethod("getBlockUninstallForUser", String.class, int.class).invoke(pm, pkg, user);
        System.out.println(pkg + " user " + user + ": blockUninstall=" + blocked);
    }
}
