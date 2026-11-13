# Acceptance-only crash entrypoints: retain call sites but obfuscate their names.
# These classes live outside the plugin's broad ru.apptracer.flutter keep rule.
-keep,allowobfuscation class ru.apptracer.verification.** { *; }
-keepattributes SourceFile,LineNumberTable
# Task 23 release reproducer invokes startup reflectively after managed purge.
-keep class ru.ok.tracer.startup.TracerStartup { *; }
