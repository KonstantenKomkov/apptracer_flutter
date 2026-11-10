package audit.tracer161

object BetaKotlinFailure {
    @JvmStatic fun trigger(): Nothing = throw IllegalStateException("beta-kotlin-fixture")
}
