package com.leanbitlab.ltvL;

/**
 * Tiny command-line entry point, run as the {@code shell} user through Hearth's own loopback adb connection
 * (see {@link KidsAppAccess}), that sets or reads Android's per-user "block uninstall" flag for one package.
 *
 * <p>Why it exists: the flag is what keeps a kid profile's copy of Hearth / HearthTube from being removed by
 * Google TV's launcher at a profile start. No {@code pm} verb exposes it; the only entry point is
 * {@code IPackageManager.setBlockUninstallForUser}, which just needs the {@code DELETE_PACKAGES} permission that
 * the {@code shell} user holds. So Hearth runs THIS class as shell:
 *
 * <pre>CLASSPATH=&lt;Hearth's base.apk&gt; app_process /system/bin \
 *     com.leanbitlab.ltvL.KidsBlockUninstallMain &lt;package&gt; &lt;userId&gt; [true|false]</pre>
 *
 * <p>USER CONTROL: this is never invoked on its own. It runs only as one step of a parent-initiated
 * "Add Hearth to kids' profiles" / "Remove Hearth from kids' profiles" action (see {@link KidsAppAccess}), and only
 * ever for Hearth's own two packages. Setting {@code true} protects a copy; setting {@code false} releases it so it
 * can be uninstalled again. Reading (no third argument) changes nothing.
 *
 * <p>Reflection-only so it has no compile-time dependency on hidden framework APIs.
 */
public final class KidsBlockUninstallMain {

    private KidsBlockUninstallMain() {
    }

    public static void main(String[] args) {
        if (args.length < 2 || args.length > 3) {
            System.err.println("usage: KidsBlockUninstallMain <package> <userId> [true|false]");
            System.exit(2);
            return;
        }
        String packageName = args[0];
        int userId;
        try {
            userId = Integer.parseInt(args[1]);
        } catch (NumberFormatException e) {
            System.err.println("userId must be an integer");
            System.exit(2);
            return;
        }

        try {
            Object binder = Class.forName("android.os.ServiceManager")
                    .getMethod("getService", String.class).invoke(null, "package");
            Object pm = Class.forName("android.content.pm.IPackageManager$Stub")
                    .getMethod("asInterface", Class.forName("android.os.IBinder")).invoke(null, binder);
            Class<?> ipm = Class.forName("android.content.pm.IPackageManager");

            if (args.length == 3) {
                if (!"true".equals(args[2]) && !"false".equals(args[2])) {
                    System.err.println("third argument must be true or false");
                    System.exit(2);
                    return;
                }
                boolean block = Boolean.parseBoolean(args[2]);
                Object ok = ipm.getMethod("setBlockUninstallForUser", String.class, boolean.class, int.class)
                        .invoke(pm, packageName, block, userId);
                System.out.println("setBlockUninstallForUser(" + packageName + ", " + block + ", user " + userId
                        + ") returned " + ok);
            }
            Object blocked = ipm.getMethod("getBlockUninstallForUser", String.class, int.class)
                    .invoke(pm, packageName, userId);
            // Printed in a fixed shape so the caller can parse it back: "<pkg> user <n>: blockUninstall=<bool>".
            System.out.println(packageName + " user " + userId + ": blockUninstall=" + blocked);
        } catch (Throwable t) {
            System.err.println("KidsBlockUninstallMain failed: " + t);
            System.exit(1);
        }
    }
}
