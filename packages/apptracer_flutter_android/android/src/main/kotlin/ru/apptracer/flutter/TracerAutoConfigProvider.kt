package ru.apptracer.flutter

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.util.Log

/**
 * Applies [TracerAutoConfig] at process start, so that an integration gets the
 * non-fatal rate limit without naming anything in its manifest.
 *
 * A `ContentProvider` is used for its timing and for nothing else: providers are
 * created before `Application.onCreate`, and the system creates them in
 * descending `android:initOrder`. The manifest of this package asks for `100`,
 * the Tracer SDK's own `InitializationProvider` leaves the default `0`, and that
 * one number is what puts our configuration in place before the SDK reads it.
 * The same trick, for the same reason, is how Firebase installs itself.
 *
 * Everything the configuration touches is behind [TracerAutoConfig]: the Tracer
 * SDK is a `compileOnly` dependency, so in an application that never added it
 * the first call into that class raises `NoClassDefFoundError`, and it has to be
 * caught by a method that does not itself mention the missing types.
 *
 * The provider serves no data. It is not exported, and its authority is derived
 * from the application id, so two applications on one device do not collide.
 */
class TracerAutoConfigProvider : ContentProvider() {

    override fun onCreate(): Boolean {
        try {
            if (!TracerAutoConfig.install()) {
                Log.d(TAG, "Tracer was already initialized; left its configuration alone")
            }
        } catch (error: Throwable) {
            // The Tracer SDK is absent, or the internal setter this relies on
            // is gone from a newer version. Neither is worth a crash at start:
            // the integration keeps working, at the SDK's default limit of 8
            // non-fatals per session.
            Log.d(TAG, "could not configure the Tracer SDK: $error")
        }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    private companion object {
        const val TAG = "apptracer_flutter"
    }
}
