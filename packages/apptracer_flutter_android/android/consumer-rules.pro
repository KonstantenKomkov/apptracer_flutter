# Consumer rules shipped inside the AAR, so applications get them automatically.
#
# The Tracer SDK is a compileOnly dependency of this plugin: an application that
# integrates apptracer_flutter without adding ru.ok.tracer must still build and
# run, and the plugin degrades to "collection is off" at runtime.
#
# R8 does not know that. In a minified release build it sees this plugin
# referencing classes that are not on the classpath and fails the build with
# "Missing classes detected". These rules tell it that the absence is
# deliberate.
#
# The rules are harmless when the SDK *is* present: -dontwarn only suppresses
# the warning, it does not stop R8 from processing classes that do exist, and
# ru.ok.tracer ships its own proguard.txt with whatever keeps it needs.
-dontwarn ru.ok.tracer.**
# SDK 1.4.0's CoreTracerConfiguration bytecode also references this optional
# transitive type. ConsentTracerApplication is only loaded after the SDK check.
-dontwarn javax.inject.Provider

# Reached reflectively from Dart through the method channel, never from Java, so
# nothing in a static analysis proves these members are used.
-keep class ru.apptracer.flutter.** { *; }

# Deferred 1.4.0 adapter: runtime version check, watchdog shutdown and optional
# native writer uninstall use these exact verified JVM names.
-keep class ru.ok.tracer.BuildConfig { public static java.lang.String LIBRARY_VERSION; }
-keep class ru.ok.tracer.crash.report.AnrWatchdogThread { *; }
-keep class ru.ok.tracer.minidump.Minidump { *; }

# The SDK adds this queue above its configured background executor.
-keep class ru.ok.tracer.utils.SequentialExecutor { *; }
-keep class ru.ok.tracer.utils.SequentialExecutor$QueueRunnable { *; }

# Terminal retirement of the 1.4.0 SDK's retained diagnostic stores.
-keep class ru.ok.tracer.Tracer { *; }
-keep class ru.ok.tracer.CoreTracerConfiguration { *; }
-keep class ru.ok.tracer.session.TagsStorage { *; }
-keep class ru.ok.tracer.session.TagsStorage$PrevTagsState { *; }
-keep class ru.ok.tracer.session.SessionStateStorage { *; }
-keep class ru.ok.tracer.utils.SimpleFileKeyValueStorage { *; }
-keep class ru.ok.tracer.crash.report.TracerCrashReport { *; }
-keep class ru.ok.tracer.crash.report.CrashLoggerInternal { *; }
-keep class ru.ok.tracer.crash.report.LogStorage { *; }
-keep class ru.ok.tracer.crash.report.LogStorage$PrevLogsState { *; }
-keep class ru.ok.tracer.crash.report.LogStorage$LogsState { *; }
-keep class ru.ok.tracer.crash.report.LogBuf { *; }

# Fatal admission and startup-writer stack tracking rely on these names/fields.
-keep class ru.ok.tracer.utils.ChainedUncaughtExceptionHandler { *; }
-keep class ru.ok.tracer.crash.report.TracerUncaughtExceptionHandler { *; }
