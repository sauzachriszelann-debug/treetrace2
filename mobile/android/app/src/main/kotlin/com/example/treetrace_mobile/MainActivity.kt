package com.example.treetrace_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import com.google.ar.core.ArCoreApk

class MainActivity : FlutterActivity() {
    private var pendingScan: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val photoMetadata = CameraPhotoMetadata(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "treetrace/photo_metadata")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "cameras" -> result.success(photoMetadata.cameras(call.argument<List<String>>("ids") ?: emptyList()))
                        "read" -> {
                            val path = call.argument<String>("path")
                            val id = call.argument<String>("camera_id")
                            if (path == null || id == null) result.error("input", "Capture metadata is missing.", null)
                            else result.success(photoMetadata.read(path, id))
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("metadata", "Camera information is unavailable.", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "treetrace/dbh_ar")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> {
                        val availability = ArCoreApk.getInstance().checkAvailability(this)
                        result.success(mapOf(
                            "supported" to availability.isSupported,
                            "checking" to availability.isTransient,
                            "reason" to if (availability.isSupported)
                                "Depth support will be checked when the scanner opens."
                            else "AR measurement is not available on this phone, or support is still being checked."
                        ))
                    }
                    "scan" -> {
                        if (android.os.Build.VERSION.SDK_INT < 24) result.success(mapOf(
                            "status" to "unavailable", "reason" to "Automatic DBH requires Android 7 or later."))
                        else if (pendingScan != null) result.error("busy", "A scan is already open.", null)
                        else {
                            pendingScan = result
                            startActivityForResult(Intent(this, DbhArActivity::class.java)
                                .putExtra("unified", call.argument<Boolean>("unified") == true), 1301)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Android activity result bridge for Flutter")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1301) {
            val path = data?.getStringExtra("capture_path")
            val reason = data?.getStringExtra("reason")
            pendingScan?.success(if (path != null) mapOf("path" to path)
                else mapOf("status" to if (reason != null) "unavailable" else "cancelled",
                    "reason" to (reason ?: "Scan cancelled.")))
            pendingScan = null
        }
    }
}
