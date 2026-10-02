package ru.apptracer.flutter;

import java.io.File;
import java.io.IOException;

/** Deletes a verified SDK root without following links outside that root. */
final class DiagnosticFiles {
    private DiagnosticFiles() { }

    static void clear(File root) throws IOException {
        File parent = root.getParentFile().getCanonicalFile();
        File target = new File(parent, root.getName());
        File[] siblings = parent.listFiles();
        if (siblings == null) throw new IOException("cannot inspect diagnostic parent");
        boolean present = false;
        for (File sibling : siblings) if (sibling.getName().equals(target.getName())) present = true;
        if (!present) return;
        delete(target);
        if (target.exists()) throw new IOException("diagnostic root still exists");
    }

    private static void delete(File file) throws IOException {
        // A dangling link has exists()==false but still must be unlinked.
        boolean link = !file.getCanonicalFile().equals(file.getAbsoluteFile());

        if (!link && file.isDirectory()) {
            File[] children = file.listFiles();
            if (children == null) throw new IOException("cannot list diagnostic directory");
            for (File child : children) delete(child);
        }
        if (!file.delete()) throw new IOException("cannot delete diagnostic entry");
    }
}
