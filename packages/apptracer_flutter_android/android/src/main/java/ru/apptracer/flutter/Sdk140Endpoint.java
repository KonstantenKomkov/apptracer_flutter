package ru.apptracer.flutter;

/** Tracer 1.4.0 catches provider exceptions and falls back to its default URL. */
final class Sdk140Endpoint {
    interface Source { String get(); }
    private final RevocableExecutor permission;
    private volatile Source source;

    Sdk140Endpoint(RevocableExecutor permission, Source source) {
        this.permission = permission;
        this.source = source;
    }

    void revoke() { source = null; }

    String get() {
        // Return a non-null relative URL: getApiUrl accepts it without fallback,
        // while HttpUrlConnectionHttpClient's new URL(...) fails before opening
        // a connection. A request built before revocation remains in-flight.
        if (!permission.isOpen()) return "";
        Source current = source;
        if (current == null) return "";
        String selected = current.get();
        return permission.isOpen() ? selected : "";
    }
}
