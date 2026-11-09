package com.example.treetrace_mobile

import android.content.Context
import android.graphics.BitmapFactory
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.ExifInterface
import android.os.Build
import java.io.File

/** Reads metadata only. Never edits, recompresses, logs, or uploads a photograph. */
class CameraPhotoMetadata(private val context: Context) {
    private val manager get() = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private fun details(id: String): Map<String, Any?> {
        val c = manager.getCameraCharacteristics(id)
        val size = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
        val pixels = c.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
        val active = c.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
        val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
        val logical = Build.VERSION.SDK_INT >= 28 &&
            (c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.contains(
                CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA) == true)
        // The current Flutter plugin cannot pin or report an active physical ID
        // within a logical camera. Never certify that camera as lens-locked.
        val locked = !logical && focal?.size == 1
        val width = if (size != null && pixels != null && active != null && pixels.width > 0)
            size.width.toDouble() * active.width() / pixels.width else null
        val height = if (size != null && pixels != null && active != null && pixels.height > 0)
            size.height.toDouble() * active.height() / pixels.height else null
        return mapOf("id" to id, "back" to (c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK),
            "sensor_width_mm" to width, "sensor_height_mm" to height,
            "focal_mm" to focal?.singleOrNull()?.toDouble(), "lens_locked" to locked,
            "sensor_area" to ((width ?: 0.0) * (height ?: 0.0)))
    }

    fun cameras(ids: List<String>): List<Map<String, Any?>> = ids.mapNotNull { id ->
        try { details(id) } catch (_: Exception) { null }
    }.filter { it["back"] == true }.sortedByDescending { it["sensor_area"] as Double }

    fun read(path: String, id: String): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < 24) return failure("Camera EXIF reading requires Android 7 or later.")
        // The caller can only request an app-private capture, not an arbitrary path.
        val file = File(path).canonicalFile
        val roots = listOf(context.cacheDir, context.filesDir, context.getExternalFilesDir(null)).filterNotNull()
        if (roots.none { file.path.startsWith(it.canonicalPath + File.separator) }) {
            return failure("The original camera photo could not be read.")
        }
        return try {
            val info = details(id).toMutableMap()
            if (info["back"] != true) return failure("Use the rear main camera.")
            val image = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, image)
            val exif = ExifInterface(file.path)
            info.putAll(mapOf("status" to "ok", "width" to image.outWidth, "height" to image.outHeight,
                "exif_focal_mm" to exif.getAttributeDouble(ExifInterface.TAG_FOCAL_LENGTH, Double.NaN),
                "exif_zoom" to exif.getAttributeDouble("DigitalZoomRatio", 1.0)))
            info
        } catch (_: Exception) { failure("Camera focal information is missing. Retake or skip measurement.") }
    }

    private fun failure(reason: String) = mapOf("status" to "retake", "reason" to reason, "f_px" to null)
}
