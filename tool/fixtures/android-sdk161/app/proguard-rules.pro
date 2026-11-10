# Preserve distinct Java/Kotlin call sites while allowing actual name obfuscation.
-keep,allowobfuscation class audit.tracer161.**Failure { public static *** trigger(...); }
-keepattributes SourceFile,LineNumberTable
