package ru.apptracer.flutter

/**
 * A [Throwable] that carries a Dart error across into the Tracer Android SDK.
 *
 * `TracerCrashReport.report` takes a java `Throwable`, and Tracer groups events
 * by the common part of the stack trace. A Dart error therefore has to be
 * wrapped in something whose `stackTrace` is the Dart stack rather than the JNI
 * frames that happen to be on the JVM stack at the moment of the call — those
 * are identical for every report and would collapse every Dart error in the
 * application into a single group.
 *
 * [fillInStackTrace] is overridden to a no-op so the JVM never captures its own
 * frames; the real frames are installed by [AppTracerFlutterPlugin].
 */
internal class DartError(message: String) : RuntimeException(message) {

    /**
     * Suppresses JVM stack capture. Returning `this` is the documented way to
     * make a throwable cheap and stack-less.
     */
    override fun fillInStackTrace(): Throwable = this

    override fun toString(): String {
        val msg = message
        return if (msg.isNullOrEmpty()) DART_ERROR_NAME else "$DART_ERROR_NAME: $msg"
    }

    internal companion object {
        /**
         * Rendered as the exception class in Tracer. The Dart type name is put
         * in front of the message instead, because the JVM class of the wrapper
         * is the same for every Dart error and says nothing useful.
         */
        const val DART_ERROR_NAME: String = "DartError"

        private const val UNKNOWN_CLASS = "dart"
        private const val UNKNOWN_MEMBER = "<unknown>"

        /**
         * Converts parsed Dart frames into [StackTraceElement]s.
         *
         * The mapping is chosen so that `StackTraceElement.toString()` renders
         * something a Dart developer recognises:
         *
         * ```
         * MyHomePage.build.<anonymous closure>(package:example/main.dart:78)
         * ```
         *
         * so `declaringClass`/`methodName` are split off the Dart member and the
         * full Dart URI is used as the file name.
         *
         * Address-only frames from an obfuscated AOT build keep their virtual
         * address, which is the value `flutter symbolize` resolves.
         */
        fun toStackTrace(frames: List<Map<String, Any?>>): Array<StackTraceElement> {
            val elements = ArrayList<StackTraceElement>(frames.size)
            for (frame in frames) {
                if (frame["asyncSuspension"] == true) {
                    elements.add(
                        StackTraceElement(UNKNOWN_CLASS, "<asynchronous suspension>", null, 0)
                    )
                    continue
                }

                val member = frame["member"] as? String
                val uri = frame["uri"] as? String
                val line = (frame["line"] as? Number)?.toInt() ?: 0

                if (member != null) {
                    val lastDot = member.lastIndexOf('.')
                    val declaringClass =
                        if (lastDot > 0) member.substring(0, lastDot) else UNKNOWN_CLASS
                    val methodName =
                        if (lastDot > 0) member.substring(lastDot + 1) else member
                    elements.add(StackTraceElement(declaringClass, methodName, uri, line))
                    continue
                }

                val virt = frame["virtAddress"] as? String
                if (virt != null) {
                    val symbol = frame["symbol"] as? String
                    elements.add(
                        StackTraceElement(
                            "dart.unsymbolized",
                            symbol ?: "frame",
                            "virt $virt",
                            0
                        )
                    )
                    continue
                }

                val raw = frame["raw"] as? String
                elements.add(StackTraceElement(UNKNOWN_CLASS, UNKNOWN_MEMBER, raw, 0))
            }
            return elements.toTypedArray()
        }
    }
}
