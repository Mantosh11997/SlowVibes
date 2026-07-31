package com.slowvibes.slow_vibes

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException

/**
 * Hosts a small MediaStore bridge so downloaded tracks land in the phone's
 * public Music folder.
 *
 * Why a platform channel instead of a package: everything written through
 * `path_provider` goes to app-private storage, which no file manager or music
 * player can see. Publishing into the shared Music collection requires
 * MediaStore, and doing it here keeps both the dependency list and the fragile
 * AGP 9 / Kotlin-plugin setup this project already works around untouched.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "slowvibes/mediastore"

        /** Sub-folder created inside the public Music directory. */
        private const val ALBUM_DIR = "Slow Vibes"

        /** Arbitrary; only needs to be unique within this Activity. */
        private const val REQUEST_WRITE_STORAGE = 4711
    }

    /** Set while a pre-Android-10 permission prompt is on screen. */
    private var pendingResult: MethodChannel.Result? = null
    private var pendingCall: MethodCall? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToMusic" -> handleSaveToMusic(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleSaveToMusic(call: MethodCall, result: MethodChannel.Result) {
        // Android 10 (API 29) introduced scoped storage: MediaStore writes into
        // the shared collection need no permission at all. Below that the file
        // is written directly, and WRITE_EXTERNAL_STORAGE is still required.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingCall = call
            pendingResult = result
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_WRITE_STORAGE,
            )
            return
        }

        performSave(call, result)
    }

    private fun performSave(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("path")
        val displayName = call.argument<String>("name")
        val mimeType = call.argument<String>("mimeType") ?: "audio/mpeg"

        if (sourcePath.isNullOrEmpty() || displayName.isNullOrEmpty()) {
            result.error("bad_args", "path and name are required", null)
            return
        }

        val source = File(sourcePath)
        if (!source.exists()) {
            result.error("missing_source", "Rendered file no longer exists", null)
            return
        }

        try {
            result.success(insertIntoMediaStore(source, displayName, mimeType))
        } catch (e: Exception) {
            result.error("save_failed", e.message ?: "MediaStore write failed", null)
        }
    }

    /**
     * Copies [source] into the shared Music collection and returns the
     * user-visible path.
     */
    private fun insertIntoMediaStore(
        source: File,
        displayName: String,
        mimeType: String,
    ): String {
        val resolver = applicationContext.contentResolver
        val isScoped = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        val collection: Uri = if (isScoped) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
            put(MediaStore.Audio.Media.IS_MUSIC, 1)
            put(MediaStore.Audio.Media.TITLE, displayName.substringBeforeLast('.'))

            if (isScoped) {
                put(
                    MediaStore.Audio.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_MUSIC + File.separator + ALBUM_DIR,
                )
                // Hides the row from other apps until the bytes are written, so
                // a music player cannot index a half-copied file.
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_MUSIC,
                    ),
                    ALBUM_DIR,
                )
                if (!dir.exists()) dir.mkdirs()
                put(MediaStore.Audio.Media.DATA, File(dir, displayName).absolutePath)
            }
        }

        val uri = resolver.insert(collection, values)
            ?: throw IOException("MediaStore refused the insert")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            } ?: throw IOException("Could not open the destination for writing")
        } catch (e: Exception) {
            // Leave no orphaned row behind if the copy dies part-way.
            resolver.delete(uri, null, null)
            throw e
        }

        if (isScoped) {
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) },
                null,
                null,
            )
        }

        return "Music/$ALBUM_DIR/$displayName"
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_WRITE_STORAGE) return

        val call = pendingCall
        val result = pendingResult
        pendingCall = null
        pendingResult = null
        if (call == null || result == null) return

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        if (granted) {
            performSave(call, result)
        } else {
            result.error(
                "permission_denied",
                "Storage permission is needed to save into the Music folder",
                null,
            )
        }
    }
}
