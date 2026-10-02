package ru.apptracer.flutter;

import java.lang.reflect.Proxy;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.concurrent.atomic.AtomicInteger;

/** Uses the real CoreTracerConfiguration getter to exercise vendor fallback. */
public final class Sdk140EndpointTest {
    @SuppressWarnings("deprecation") // Matches the inspected Android SDK URL client.
    public static void main(String[] args) throws Exception {
        Class<?> provider = Class.forName("javax.inject.Provider");
        Class<?> builderType = Class.forName("ru.ok.tracer.CoreTracerConfiguration$Builder");
        RevocableExecutor permission = new RevocableExecutor(Runnable::run);
        AtomicInteger queries = new AtomicInteger();
        Sdk140Endpoint endpoint = new Sdk140Endpoint(permission, () -> {
            queries.incrementAndGet();
            return "https://sdk-api.apptracer.ru";
        });
        Object builder = builderType.getConstructor().newInstance();
        Object apiProvider = Proxy.newProxyInstance(provider.getClassLoader(), new Class<?>[]{provider},
                (proxy, method, arguments) -> endpoint.get());
        builderType.getMethod("provideApiUrl", provider).invoke(builder, apiProvider);
        Object config = builderType.getMethod("build").invoke(builder);
        check(config.getClass().getMethod("getApiUrl").invoke(config)
                .equals("https://sdk-api.apptracer.ru"), "authorized endpoint lost");
        permission.close();
        endpoint.revoke();
        java.lang.reflect.Field source = Sdk140Endpoint.class.getDeclaredField("source");
        source.setAccessible(true);
        check(source.get(endpoint) == null, "revoked endpoint retained host configuration");
        String blocked = (String) config.getClass().getMethod("getApiUrl").invoke(config);
        check(blocked.isEmpty(), "vendor fallback bypassed endpoint revocation");
        check(queries.get() == 1, "revoked endpoint queried host provider");
        for (String path : new String[]{"/api/crash/upload", "/api/session/upload", "/api/crash/uploadBatch"}) {
            try {
                new URL(blocked + path);
                throw new AssertionError("revoked address accepted for connection");
            } catch (MalformedURLException expected) { }
        }
        System.out.println("Sdk140Endpoint: vendor getter blocks revoked URLs before connection");
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
