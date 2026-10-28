package com.thesiegs.hearth;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

/** Made-up PIN screens (node trees, a clock, a D-pad) for running recipes without a TV. No real PINs or names. */
final class PinFakes {
    private PinFakes() {
    }

    // ---- The recipe files ----

    static String file(String path) {
        for (String base : new String[] {"", "app/", "android/app/"}) {
            File f = new File(base + path);
            if (f.isFile()) {
                try {
                    return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
                } catch (Exception e) {
                    throw new AssertionError(e);
                }
            }
        }
        throw new AssertionError("no " + path + " from " + new File("").getAbsolutePath());
    }

    /** Hearth's own recipes (the asset). */
    static String builtInFile() {
        return file("src/main/assets/pin-recipes.json");
    }

    /** The copy in the repository's pin-entry folder, which installed copies fetch. */
    static String repoFile() {
        return file("../../pin-entry/recipes.json");
    }

    static Map<String, PinRecipeSpec> builtIn() {
        return PinRecipeSpec.parseFile(builtInFile());
    }

    static PinRecipeSpec spec(String slot, String pkg) {
        PinRecipeSpec spec = builtIn().get(PinRecipeSpec.key(slot, pkg));
        if (spec == null) throw new AssertionError("no built-in recipe for " + pkg);
        return spec;
    }

    static DataPinRecipe recipe(String slot, String pkg, Clock clock) {
        return new DataPinRecipe(spec(slot, pkg), clock);
    }

    // ---- Nodes ----

    static final class Node implements PinNode {
        String pkg;
        String id;
        String text;
        String description;
        boolean clickable;
        boolean visible = true;
        boolean showingHint;
        Node parent;
        final List<Node> children = new ArrayList<>();
        int clicks;
        boolean clickWorks = true;
        String setTo;
        /** What a click does to the screen (a digit into the field, say). */
        Runnable onClick;

        Node(String pkg) {
            this.pkg = pkg;
        }

        Node id(String id) {
            this.id = pkg + ":id/" + id;
            return this;
        }

        Node text(String text) {
            this.text = text;
            return this;
        }

        Node desc(String description) {
            this.description = description;
            return this;
        }

        Node clickable() {
            clickable = true;
            return this;
        }

        Node hidden() {
            visible = false;
            return this;
        }

        Node add(Node... nodes) {
            for (Node n : nodes) {
                n.parent = this;
                children.add(n);
            }
            return this;
        }

        void remove(Node child) {
            children.remove(child);
            child.parent = null;
        }

        @Override
        public CharSequence text() {
            return text;
        }

        @Override
        public CharSequence description() {
            return description;
        }

        @Override
        public boolean isClickable() {
            return clickable;
        }

        @Override
        public boolean isVisible() {
            return visible;
        }

        @Override
        public boolean isShowingHint() {
            return showingHint;
        }

        @Override
        public CharSequence packageName() {
            return pkg;
        }

        @Override
        public PinNode parent() {
            return parent;
        }

        @Override
        public int childCount() {
            return children.size();
        }

        @Override
        public PinNode child(int index) {
            return children.get(index);
        }

        private void all(List<Node> out) {
            out.add(this);
            for (Node c : children) c.all(out);
        }

        @Override
        public List<PinNode> findById(String fullId) {
            List<Node> all = new ArrayList<>();
            all(all);
            List<PinNode> out = new ArrayList<>();
            for (Node n : all) {
                if (fullId.equals(n.id)) out.add(n);
            }
            return out;
        }

        @Override
        public List<PinNode> findByText(String find) {
            List<Node> all = new ArrayList<>();
            all(all);
            List<PinNode> out = new ArrayList<>();
            String f = find.toLowerCase(Locale.ROOT);
            for (Node n : all) {
                if ((n.text != null && n.text.toLowerCase(Locale.ROOT).contains(f))
                        || (n.description != null && n.description.toLowerCase(Locale.ROOT).contains(f))) {
                    out.add(n);
                }
            }
            return out;
        }

        @Override
        public boolean click() {
            if (!clickWorks) return false;
            clicks++;
            if (onClick != null) onClick.run();
            return true;
        }

        @Override
        public boolean setText(char[] digits) {
            setTo = new String(digits);
            return true;
        }

        @Override
        public boolean sameAs(PinNode other) {
            return this == other;
        }
    }

    // ---- Time ----

    /** A clock that only moves when told, running what was due on the way. */
    static final class Clock implements PinNode.Ticker {
        long now = 1_000;
        private final TreeMap<Long, List<Runnable>> mDue = new TreeMap<>();

        @Override
        public long now() {
            return now;
        }

        @Override
        public void later(Runnable check, long delayMs) {
            mDue.computeIfAbsent(now + delayMs, k -> new ArrayList<>()).add(check);
        }

        @Override
        public void cancel() {
            mDue.clear();
        }

        boolean idle() {
            return mDue.isEmpty();
        }

        void advance(long ms) {
            long until = now + ms;
            while (!mDue.isEmpty() && mDue.firstKey() <= until) {
                Map.Entry<Long, List<Runnable>> next = mDue.pollFirstEntry();
                now = next.getKey();
                for (Iterator<Runnable> it = next.getValue().iterator(); it.hasNext(); ) it.next().run();
            }
            now = until;
        }
    }

    /** The window in front, and D-pad presses recorded (and handed to a keypad that moves its focus). */
    static class Host implements PinNode.Host {
        PinNode root;
        boolean canMove = true;
        final List<Integer> presses = new ArrayList<>();
        Keypad keypad;

        @Override
        public PinNode root() {
            return root;
        }

        @Override
        public boolean canMoveFocus() {
            return canMove;
        }

        @Override
        public void press(int key) {
            presses.add(key);
            if (keypad != null) keypad.press(key);
        }
    }

    /**
     * A D-pad keypad as on screen (labels by row, "" for no key, "DEL" for Delete), which says the newly focused key's
     * label the way the app does, and what pressing OK on it does.
     */
    static final class Keypad {
        final String[][] grid;
        int row, col;
        final List<String> entered = new ArrayList<>();
        /** Says the focused key (speech or a focus event). */
        java.util.function.Consumer<String> sayFocus;
        /** Says what OK did (the digit's echo, a count). */
        java.util.function.Consumer<String> sayOk;

        Keypad(String[][] grid, String start) {
            this.grid = grid;
            for (int r = 0; r < grid.length; r++) {
                for (int c = 0; c < grid[r].length; c++) {
                    if (start.equals(grid[r][c])) {
                        row = r;
                        col = c;
                    }
                }
            }
        }

        String focused() {
            return grid[row][col];
        }

        void press(int key) {
            if (key == PinNode.Host.CENTER) {
                entered.add(focused());
                if (sayOk != null) sayOk.accept(focused());
                return;
            }
            int r = row + (key == PinNode.Host.DOWN ? 1 : key == PinNode.Host.UP ? -1 : 0);
            int c = col + (key == PinNode.Host.RIGHT ? 1 : key == PinNode.Host.LEFT ? -1 : 0);
            if (r < 0 || r >= grid.length || c < 0 || c >= grid[r].length || grid[r][c].isEmpty()) return;
            row = r;
            col = c;
            if (sayFocus != null) sayFocus.accept(focused());
        }
    }

    static List<String> list(String... s) {
        return Arrays.asList(s);
    }
}
