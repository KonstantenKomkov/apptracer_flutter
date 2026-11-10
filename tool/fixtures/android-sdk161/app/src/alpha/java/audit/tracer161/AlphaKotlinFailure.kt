package audit.tracer161

object AlphaKotlinFailure {
    @JvmStatic fun trigger(): Nothing = throw IllegalStateException("alpha-kotlin-fixture")
}
