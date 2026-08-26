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

# Reached reflectively from Dart through the method channel, never from Java, so
# nothing in a static analysis proves these members are used.
-keep class ru.apptracer.flutter.** { *; }
