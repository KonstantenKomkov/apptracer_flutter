package ru.apptracer.flutter;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.Collections;
import java.util.Map;

/** Standalone check: run with Flutter/Android libraries but without vendor SDK. */
public final class MissingSdkLifecycleTest {
    public static void main(String[] args) {
        try {
            Class.forName("ru.ok.tracer.Tracer");
            throw new AssertionError("test must run without the vendor SDK");
        } catch (ClassNotFoundException expected) { }
        AppTracerFlutterPlugin plugin = new AppTracerFlutterPlugin();
        missing(invoke(plugin, "getCollectionState", null));
        Map<?, ?> disabled = (Map<?, ?>) invoke(plugin, "startCollection",
                Collections.singletonMap("isCollectionEnabled", false));
        check("disabled".equals(disabled.get("state")), "disabled start permitted collection");
        for (String method : new String[]{"recordError", "recordLog", "setCustomKey", "removeCustomKey", "setUserId"}) {
            check(invoke(plugin, method, Collections.emptyMap()) == null, "off event was accepted");
        }
        invoke(plugin, "stopCollection", null);
        missing(invoke(new AppTracerFlutterPlugin(), "getCollectionState", null));
        System.out.println("MissingSdkLifecycle: state/off events/process stop safe without vendor classes");
    }
    private static Object invoke(AppTracerFlutterPlugin plugin, String name, Object arguments) {
        Object[] returned = new Object[]{new Object()};
        plugin.onMethodCall(new MethodCall(name, arguments), new MethodChannel.Result() {
            public void success(Object value) { returned[0] = value; }
            public void error(String code, String message, Object details) { throw new AssertionError(code); }
            public void notImplemented() { throw new AssertionError("missing method: " + name); }
        });
        return returned[0];
    }
    private static void missing(Object result) {
        Map<?, ?> state = (Map<?, ?>) result;
        check("unsupported".equals(state.get("state")) && "sdk_missing".equals(state.get("reason")),
                "missing SDK state was incorrect: " + state);
    }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
}
