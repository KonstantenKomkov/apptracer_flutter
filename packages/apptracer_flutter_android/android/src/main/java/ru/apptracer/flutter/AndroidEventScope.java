package ru.apptracer.flutter;

import ru.ok.tracer.Tracer;

import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

final class AndroidEventScope {
    private static final Object LOCK = new Object();
    private static final Set<String> PERSISTENT_KEYS = new LinkedHashSet<>();

    private AndroidEventScope() { }

    static void setPersistentProperty(String key, String value) {
        synchronized (LOCK) {
            String nativeKey = truncate(key, 32);
            Tracer.setCustomProperty(nativeKey, value);
            if (value == null) PERSISTENT_KEYS.remove(nativeKey);
            else PERSISTENT_KEYS.add(nativeKey);
        }
    }

    static void clearPersistentProperties() {
        synchronized (LOCK) {
            PERSISTENT_KEYS.clear();
        }
    }

    static void withEventProperties(Map<String, String> eventProperties, Runnable report) throws Throwable {
        synchronized (LOCK) {
            Map<String, String> desired = new LinkedHashMap<>();
            for (String key : PERSISTENT_KEYS) desired.put(key, null);
            for (Map.Entry<String, String> entry : eventProperties.entrySet()) {
                // SDK 1.6.2 stores 32 UTF-16 units per key and 64 per value.
                desired.put(truncate(entry.getKey(), 32), truncate(entry.getValue(), 64));
            }
            Map<String, String> current = currentProperties();
            Map<String, String> changes = new LinkedHashMap<>();
            Map<String, String> previous = new LinkedHashMap<>();
            // SDK 1.6.2 discards the batch if the last entry is unchanged.
            for (Map.Entry<String, String> entry : desired.entrySet()) {
                String key = entry.getKey();
                if (!Objects.equals(current.get(key), entry.getValue())) {
                    changes.put(key, entry.getValue());
                    previous.put(key, current.get(key));
                }
            }
            if (changes.isEmpty()) {
                report.run();
                return;
            }

            Throwable failure = null;
            try {
                Tracer.setCustomProperties(changes);
                // The SDK logs storage exceptions and can return without applying the filter.
                if (hasProperties(changes)) report.run();
            } catch (Throwable error) {
                failure = error;
            } finally {
                try {
                    // A native host can write directly to Tracer inside report().
                    // Only undo values that still belong to this event.
                    Map<String, String> live = currentProperties();
                    Map<String, String> restore = new LinkedHashMap<>();
                    for (Map.Entry<String, String> entry : previous.entrySet()) {
                        String key = entry.getKey();
                        if (Objects.equals(live.get(key), changes.get(key))) {
                            restore.put(key, entry.getValue());
                        }
                    }
                    if (!restore.isEmpty()) Tracer.setCustomProperties(restore);
                } catch (Throwable error) {
                    if (failure == null) failure = error;
                    else failure.addSuppressed(error);
                }
            }
            if (failure != null) throw failure;
        }
    }

    private static boolean hasProperties(Map<String, String> expected) {
        Map<String, String> current = currentProperties();
        for (Map.Entry<String, String> entry : expected.entrySet()) {
            if (!Objects.equals(current.get(entry.getKey()), entry.getValue())) return false;
        }
        return true;
    }

    private static Map<String, String> currentProperties() {
        return Tracer.INSTANCE.getStateStorage().getCurrentSystemState().getProperties();
    }

    private static String truncate(String value, int limit) {
        return value != null && value.length() > limit ? value.substring(0, limit) : value;
    }
}
