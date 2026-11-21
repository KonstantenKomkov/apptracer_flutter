package ru.apptracer.flutter;

import ru.ok.tracer.Tracer;

import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

final class AndroidEventScope {
    private static final Object LOCK = new Object();
    private static final Set<String> PERSISTENT_KEYS = new LinkedHashSet<>();

    private AndroidEventScope() { }

    static void setPersistentProperty(String key, String value) {
        synchronized (LOCK) {
            PERSISTENT_KEYS.add(key);
            Tracer.setCustomProperty(key, value);
        }
    }

    static void clearPersistentProperties() {
        synchronized (LOCK) {
            PERSISTENT_KEYS.clear();
        }
    }

    static void withEventProperties(Map<String, String> eventProperties, Runnable report) throws Throwable {
        synchronized (LOCK) {
            Set<String> affectedKeys = new LinkedHashSet<>(PERSISTENT_KEYS);
            affectedKeys.addAll(eventProperties.keySet());
            Map<String, String> current = Tracer.INSTANCE.getStateStorage()
                    .getCurrentSystemState().getProperties();
            Map<String, String> previous = new HashMap<>();
            for (String key : affectedKeys) {
                previous.put(key, current.get(normalize(key)));
            }

            Throwable failure = null;
            try {
                for (String key : PERSISTENT_KEYS) {
                    if (!eventProperties.containsKey(key)) Tracer.setCustomProperty(key, null);
                }
                for (Map.Entry<String, String> property : eventProperties.entrySet()) {
                    Tracer.setCustomProperty(property.getKey(), property.getValue());
                }
                report.run();
            } catch (Throwable error) {
                failure = error;
            } finally {
                for (Map.Entry<String, String> property : previous.entrySet()) {
                    try {
                        Tracer.setCustomProperty(property.getKey(), property.getValue());
                    } catch (Throwable error) {
                        if (failure == null) failure = error;
                        else failure.addSuppressed(error);
                    }
                }
            }
            if (failure != null) throw failure;
        }
    }

    private static String normalize(String key) {
        return key.substring(0, Math.min(key.length(), 32));
    }
}
