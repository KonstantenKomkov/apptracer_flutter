package audit.tracer161;

final class VariantCrash {
    static void trigger() {
        if (android.os.SystemClock.uptimeMillis() % 2 == 0) AlphaJavaFailure.trigger();
        else AlphaKotlinFailure.trigger();
    }
}
