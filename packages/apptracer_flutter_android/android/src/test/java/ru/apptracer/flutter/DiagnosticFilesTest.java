package ru.apptracer.flutter;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;

public final class DiagnosticFilesTest {
    public static void main(String[] args) throws Exception {
        Path base = Files.createTempDirectory("tracer-purge-check");
        try {
            Path root = base.resolve("tracer");
            Path report = root.resolve("crashes/pending/report");
            Files.createDirectories(report.getParent());
            Files.write(report, new byte[] { 1, 2, 3 });
            Path outside = base.resolve("other-app-data");
            Files.createDirectory(outside);
            Path kept = outside.resolve("keep");
            Files.write(kept, new byte[] { 9 });
            Files.createSymbolicLink(root.resolve("external-link"), outside);
            Files.createSymbolicLink(root.resolve("dangling-link"), base.resolve("absent"));
            DiagnosticFiles.clear(root.toFile());
            if (Files.exists(root)) throw new AssertionError("pending diagnostics survived");
            if (!Files.exists(kept)) throw new AssertionError("purge escaped SDK root");
            DiagnosticFiles.clear(root.toFile()); // repeat and never-started roots
            Path linkedRoot = base.resolve("tracer");
            Files.createSymbolicLink(linkedRoot, outside);
            DiagnosticFiles.clear(linkedRoot.toFile());
            if (!Files.exists(kept)) throw new AssertionError("root link followed");
            System.out.println("DiagnosticFiles: reports removed; external and dangling links handled; repeat safe");
        } finally {
            delete(base.toFile());
        }
    }
    private static void delete(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) delete(child);
        file.delete();
    }
}
