package com.example.treetrace_mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix as GlMatrix
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.google.ar.core.*
import com.google.ar.core.exceptions.NotYetAvailableException
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** One AR-owned camera; never runs Flutter's camera concurrently.
 * Ground selection establishes a local horizontal datum, not an object scale.
 * Native camera, intrinsics, raw depth and pose are taken from the SAME Frame.
 */
class DbhArActivity : Activity(), GLSurfaceView.Renderer {
    private lateinit var surface: GLSurfaceView
    private lateinit var message: TextView
    private lateinit var action: Button
    private var partialButton: Button? = null
    private var session: Session? = null
    private var resumed = false
    private var installRequested = false
    private var ground: Anchor? = null
    private var groundPlane: Plane? = null
    @Volatile private var requestedAction = false
    private var viewWidth = 1
    private var viewHeight = 1
    private var texture = 0
    private var program = 0
    private var lastMessage = ""
    private var lastDepthTimestamp = 0L
    private var unified = false
    private var trunkPayload: JSONObject? = null
    @Volatile private var finishPartial = false
    @Volatile private var targetLine: FloatArray? = null
    private lateinit var guide: View
    private var crownStep = false
    private var finishing = false
    private var stableSince = 0L
    private var lastElevation = Double.NaN
    private var lastDistance = Double.NaN
    private var lastCameraAnchor: Anchor? = null

    private val vertices = floats(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val textureCoords = floats(FloatArray(8))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        unified = intent.getBooleanExtra("unified", false)
        surface = GLSurfaceView(this).apply {
            setEGLContextClientVersion(2)
            preserveEGLContextOnPause = true
            setRenderer(this@DbhArActivity)
        }
        val root = FrameLayout(this)
        root.addView(surface)
        guide = object : View(this) {
            private val pen = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE; strokeWidth = 4f; style = Paint.Style.STROKE
            }
            override fun onDraw(canvas: Canvas) {
                val cx = width / 2f; val cy = height / 2f
                val halfWidth = width * 0.30f; val halfHeight = height * 0.17f
                canvas.drawRoundRect(cx - halfWidth, cy - halfHeight,
                    cx + halfWidth, cy + halfHeight, 20f, 20f, pen)
                canvas.drawLine(cx - 22, cy, cx + 22, cy, pen)
                canvas.drawLine(cx, cy - 22, cx, cy + 22, pen)
                targetLine?.let { line ->
                    pen.color = Color.rgb(150, 255, 150)
                    canvas.drawLine(line[0], line[1], line[2], line[3], pen)
                    pen.style = Paint.Style.FILL; pen.textSize = 32f
                    canvas.drawText("1.3 m above selected base", line[0], line[1] - 12, pen)
                    pen.style = Paint.Style.STROKE; pen.color = Color.WHITE
                }
            }
        }
        root.addView(guide, FrameLayout.LayoutParams(-1, -1))
        message = TextView(this).apply {
            setTextColor(Color.WHITE); textSize = 17f; setPadding(20, 28, 20, 24)
            setBackgroundColor(0xB0000000.toInt())
            text = "1 of 3: Point at the tree base. Move your phone slowly."
        }
        root.addView(message, FrameLayout.LayoutParams(-1, -2, Gravity.TOP))
        val buttons = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        action = Button(this).apply {
            text = "Mark tree base"
            setOnClickListener { requestedAction = true }
        }
        buttons.addView(action)
        buttons.addView(Button(this).apply {
            text = "Start over"
            setOnClickListener {
                surface.queueEvent {
                    ground?.detach(); ground = null; groundPlane = null
                    trunkPayload = null; crownStep = false; targetLine = null
                    resetStability()
                    requestedAction = false
                    tell("1 of 3: Point at the tree base.")
                }
                action.text = "Mark tree base"
                partialButton?.text = "Photo only"
            }
        })
        if (unified) {
            partialButton = Button(this).apply {
                text = "Photo only"
                setOnClickListener { finishPartial = true }
            }
            buttons.addView(partialButton)
        }
        buttons.addView(Button(this).apply { text = "Cancel"; setOnClickListener { finish() } })
        root.addView(buttons, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 41)
            return
        }
        try {
            if (session == null) {
                if (ArCoreApk.getInstance().requestInstall(this, !installRequested) ==
                    ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                    installRequested = true
                    return
                }
                val created = Session(this)
                if (!created.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                    created.close()
                    unavailable("This phone does not support the depth camera required for automatic DBH.")
                    return
                }
                created.configure(Config(created).apply {
                    depthMode = Config.DepthMode.AUTOMATIC
                    planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    focusMode = Config.FocusMode.AUTO
                })
                session = created
            }
            session?.resume()
            resumed = true
            surface.onResume()
        } catch (_: Exception) {
            unavailable("The AR camera could not start. Check Google Play Services for AR and camera permission.")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 41 && (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED)) {
            unavailable("Camera permission is required for automatic DBH.")
        }
    }

    override fun onPause() {
        // Stop GL updates before pausing the session to avoid update/pause races.
        surface.onPause()
        if (resumed) session?.pause()
        resumed = false
        requestedAction = false
        resetStability()
        super.onPause()
    }

    override fun onDestroy() {
        ground?.detach()
        lastCameraAnchor?.detach()
        session?.close()
        super.onDestroy()
    }

    private fun unavailable(reason: String) {
        setResult(RESULT_CANCELED, Intent().putExtra("reason", reason))
        finish()
    }

    private fun tell(text: String) {
        if (text != lastMessage) {
            lastMessage = text
            runOnUiThread { message.text = text }
        }
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        texture = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        fun shader(type: Int, source: String): Int = GLES20.glCreateShader(type).also {
            GLES20.glShaderSource(it, source); GLES20.glCompileShader(it)
        }
        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, shader(GLES20.GL_VERTEX_SHADER,
            "attribute vec2 position; attribute vec2 uv; varying vec2 tex; void main(){gl_Position=vec4(position,0.,1.);tex=uv;}"))
        GLES20.glAttachShader(program, shader(GLES20.GL_FRAGMENT_SHADER,
            "#extension GL_OES_EGL_image_external : require\nprecision mediump float; uniform samplerExternalOES camera; varying vec2 tex; void main(){gl_FragColor=texture2D(camera,tex);}"))
        GLES20.glLinkProgram(program)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        viewWidth = width; viewHeight = height
        GLES20.glViewport(0, 0, width, height)
    }

    @Suppress("DEPRECATION")
    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        val active = session ?: return
        try {
            active.setCameraTextureName(texture)
            active.setDisplayGeometry(windowManager.defaultDisplay.rotation, viewWidth, viewHeight)
            val frame = active.update()
            frame.transformCoordinates2d(Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                vertices, Coordinates2d.TEXTURE_NORMALIZED, textureCoords)
            drawCamera()
            if (finishing) return
            if (finishPartial) {
                finishPartial = false
                val partial = trunkPayload ?: JSONObject().also { payload ->
                    frame.acquireCameraImage().use { image ->
                        payload.put("species_image_base64", Base64.encodeToString(uprightJpeg(frame, image), Base64.NO_WRAP))
                    }
                }
                partial.put("height_reason", "Height skipped by user.")
                complete(partial)
                return
            }
            if (frame.camera.trackingState != TrackingState.TRACKING) {
                requestedAction = false
                targetLine = null
                guide.postInvalidate()
                resetStability()
                tell("Move slowly in good light so the camera can track the tree.")
                return
            }
            val doAction = requestedAction
            requestedAction = false
            if (ground == null) {
                val hit = frame.hitTest(viewWidth / 2f, viewHeight / 2f).firstOrNull {
                    val plane = it.trackable as? Plane
                    plane != null && plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                        plane.trackingState == TrackingState.TRACKING && plane.isPoseInPolygon(it.hitPose) &&
                        it.distance in 0.5f..5f
                }
                tell(if (hit == null) "1 of 3: Aim + where the trunk meets level ground. Move slowly."
                    else "1 of 3: Ground found. Aim + at the tree base, then tap Mark tree base.")
                if (doAction && hit != null) {
                    ground = hit.createAnchor()
                    groundPlane = hit.trackable as Plane
                    runOnUiThread { action.text = "Capture trunk" }
                }
                return
            }
            if (ground?.trackingState != TrackingState.TRACKING || groundPlane?.trackingState != TrackingState.TRACKING) {
                tell("Tree base lost. Tap Start over.")
                return
            }
            if (unified && crownStep) {
                targetLine = null
                guide.postInvalidate()
                updateCrown(frame, doAction)
                return
            }
            updateMetricGuide(frame)
            val forward = frame.camera.displayOrientedPose.getTransformedAxis(2, -1f)
            val elevation = Math.toDegrees(atan2(forward[1].toDouble(),
                sqrt((forward[0] * forward[0] + forward[2] * forward[2]).toDouble()))).roundToInt()
            val right = frame.camera.displayOrientedPose.getTransformedAxis(0, 1f)
            val up = frame.camera.displayOrientedPose.getTransformedAxis(1, 1f)
            val roll = Math.toDegrees(atan2(abs(right[1]).toDouble(), up[1].toDouble()))
            val cameraPose = frame.camera.pose
            val basePose = ground!!.pose
            val dx = cameraPose.tx() - basePose.tx(); val dz = cameraPose.tz() - basePose.tz()
            val distance = sqrt(dx * dx + dz * dz)
            tell("2 of 3: Frame the trunk at the green line. Move sideways, then capture.\n" +
                "${String.format(java.util.Locale.US, "%.1f", distance)} m | Angle ${elevation} degrees | " +
                (if (roll <= 15) "Level" else "Hold upright"))
            if (doAction) capture(frame)
        } catch (_: NotYetAvailableException) {
            tell("Move slowly sideways, then try Capture trunk again.")
        } catch (_: Exception) {
            tell("Camera tracking was interrupted. Restart the scan or reopen the camera.")
        }
    }

    private fun drawCamera() {
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "camera"), 0)
        val pos = GLES20.glGetAttribLocation(program, "position")
        val uv = GLES20.glGetAttribLocation(program, "uv")
        vertices.position(0); textureCoords.position(0)
        GLES20.glEnableVertexAttribArray(pos); GLES20.glEnableVertexAttribArray(uv)
        GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glVertexAttribPointer(uv, 2, GLES20.GL_FLOAT, false, 0, textureCoords)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(pos); GLES20.glDisableVertexAttribArray(uv)
    }

    private fun capture(frame: Frame) {
        frame.acquireCameraImage().use { image ->
            frame.acquireRawDepthImage16Bits().use { depth ->
                frame.acquireRawDepthConfidenceImage().use { confidence ->
                    if (abs(image.timestamp - depth.timestamp) > 100_000_000L ||
                        confidence.timestamp != depth.timestamp || depth.timestamp == lastDepthTimestamp) {
                        tell("Wait for fresh depth. Move slightly sideways and capture again.")
                        return
                    }
                    lastDepthTimestamp = depth.timestamp
                    val groundY = ground!!.pose.ty()
                    val intrinsics = frame.camera.imageIntrinsics
                    val dims = intrinsics.imageDimensions
                    if (dims[0] != image.width || dims[1] != image.height) {
                        tell("Camera calibration is not ready. Reopen the scanner."); return
                    }
                    val focal = intrinsics.focalLength
                    val principal = intrinsics.principalPoint
                    val pose = frame.camera.pose
                    val samples = JSONArray()
                    val dp = depth.planes[0]
                    val cp = confidence.planes[0]
                    val buffer = dp.buffer.order(ByteOrder.LITTLE_ENDIAN)
                    val cb = cp.buffer
                    // Transform depth-texture centers into ORIGINAL CPU image pixels.
                    // Depth and camera aspect ratios can differ; never scale naively.
                    val coords = FloatArray(depth.width * depth.height * 2)
                    for (y in 0 until depth.height) for (x in 0 until depth.width) {
                        val i = (y * depth.width + x) * 2
                        coords[i] = (x + 0.5f) / depth.width
                        coords[i + 1] = (y + 0.5f) / depth.height
                    }
                    val pixels = FloatArray(coords.size)
                    frame.transformCoordinates2d(Coordinates2d.TEXTURE_NORMALIZED, coords,
                        Coordinates2d.IMAGE_PIXELS, pixels)
                    val distances = mutableListOf<Float>()
                    for (y in 0 until depth.height) for (x in 0 until depth.width) {
                        val score = (cb.get(y * cp.rowStride + x * cp.pixelStride).toInt() and 255) / 255f
                        if (score < 0.7f) continue
                        val z = (buffer.getShort(y * dp.rowStride + x * dp.pixelStride).toInt() and 65535) / 1000f
                        if (z !in 0.5f..5f) continue
                        val i = (y * depth.width + x) * 2
                        val u = pixels[i]; val v = pixels[i + 1]
                        if (u < 0 || v < 0 || u >= image.width || v >= image.height) continue
                        // Image y is down; AR camera y is up and forward is -z.
                        val world = pose.transformPoint(floatArrayOf(
                            (u - principal[0]) * z / focal[0],
                            -(v - principal[1]) * z / focal[1], -z))
                        if (abs(world[1] - groundY - 1.3f) > 0.08f) continue
                        samples.put(JSONObject().put("u", u).put("v", v).put("x", world[0])
                            .put("y", world[1]).put("z", world[2]).put("confidence", score))
                        distances.add(z)
                    }
                    if (samples.length() < 20 || samples.length() > 20000) {
                        tell("Keep both trunk edges visible at the green line. Move sideways, then capture again.")
                        return
                    }
                    distances.sort()
                    // Sensor JPEGs are unrotated. Tell segmentation how to make
                    // them upright; sample coordinates remain in sensor pixels.
                    val axis = floatArrayOf(image.width * 0.4f, image.height * 0.5f,
                        image.width * 0.6f, image.height * 0.5f)
                    val displayAxis = FloatArray(4)
                    frame.transformCoordinates2d(Coordinates2d.IMAGE_PIXELS, axis,
                        Coordinates2d.VIEW_NORMALIZED, displayAxis)
                    val rotation = ((atan2((displayAxis[3] - displayAxis[1]).toDouble(),
                        (displayAxis[2] - displayAxis[0]).toDouble()) * 180 / Math.PI / 90)
                        .roundToInt() * 90 + 360) % 360
                    val metadata = JSONObject().put("version", 1).put("source", "arcore_raw_depth")
                        .put("image_width", image.width).put("image_height", image.height)
                        .put("image_rotation_degrees", rotation)
                        .put("ground_y", groundY).put("tracking", "tracking")
                        .put("frame_timestamp_ns", image.timestamp).put("depth_timestamp_ns", depth.timestamp)
                        .put("camera_distance_m", distances[distances.size / 2]).put("samples", samples)
                    val payload = JSONObject().put("capture", metadata)
                        .put("image_base64", Base64.encodeToString(jpeg(image), Base64.NO_WRAP))
                    if (unified) {
                        payload.put("species_image_base64", Base64.encodeToString(uprightJpeg(frame, image), Base64.NO_WRAP))
                        trunkPayload = payload
                        crownStep = true
                        targetLine = null
                        resetStability()
                        runOnUiThread {
                            action.text = "Capture treetop"
                            partialButton?.text = "Skip height"
                        }
                    } else complete(payload)
                }
            }
        }
    }

    private fun resetStability() {
        stableSince = 0L
        lastElevation = Double.NaN
        lastDistance = Double.NaN
        lastCameraAnchor?.detach()
        lastCameraAnchor = null
    }

    /** Project an actual metric breast-height target anchored at the selected base. */
    private fun updateMetricGuide(frame: Frame) {
        val base = ground?.pose ?: return
        val view = FloatArray(16); val projection = FloatArray(16); val vp = FloatArray(16)
        frame.camera.getViewMatrix(view, 0)
        frame.camera.getProjectionMatrix(projection, 0, 0.1f, 100f)
        GlMatrix.multiplyMM(vp, 0, projection, 0, view, 0)
        val right = frame.camera.displayOrientedPose.getTransformedAxis(0, 1f)
        val horizontal = sqrt(right[0] * right[0] + right[2] * right[2])
        if (horizontal < 0.1f) { targetLine = null; return }
        val ends = FloatArray(4)
        for (i in 0..1) {
            val offset = if (i == 0) -0.4f else 0.4f
            val world = floatArrayOf(base.tx() + offset * right[0] / horizontal,
                base.ty() + 1.3f, base.tz() + offset * right[2] / horizontal, 1f)
            val clip = FloatArray(4)
            GlMatrix.multiplyMV(clip, 0, vp, 0, world, 0)
            if (clip[3] <= 0.1f) { targetLine = null; return }
            ends[i * 2] = (clip[0] / clip[3] + 1f) * viewWidth / 2f
            ends[i * 2 + 1] = (1f - clip[1] / clip[3]) * viewHeight / 2f
        }
        targetLine = ends
        guide.postInvalidate()
    }

    /** Height from metric base-anchor distance and the current crown sight ray.
     * All poses are read in this frame, avoiding coordinates cached across AR drift.
     */
    private fun updateCrown(frame: Frame, doAction: Boolean) {
        val base = ground!!.pose
        val camera = frame.camera.displayOrientedPose
        val forward = camera.getTransformedAxis(2, -1f)
        val up = camera.getTransformedAxis(1, 1f)
        val dx = (base.tx() - camera.tx()).toDouble()
        val dz = (base.tz() - camera.tz()).toDouble()
        val distance = sqrt(dx * dx + dz * dz)
        val horizontal = sqrt((forward[0] * forward[0] + forward[2] * forward[2]).toDouble())
        val elevation = Math.toDegrees(atan2(forward[1].toDouble(), horizontal))
        val dot = if (distance > 0 && horizontal > 0)
            (dx * forward[0] + dz * forward[2]) / (distance * horizontal) else -1.0
        val alignment = Math.toDegrees(kotlin.math.acos(dot.coerceIn(-1.0, 1.0)))
        val cameraHeight = (camera.ty() - base.ty()).toDouble()
        val right = camera.getTransformedAxis(0, 1f)
        val roll = Math.toDegrees(atan2(abs(right[1]).toDouble(), up[1].toDouble()))
        val valid = distance in 2.0..30.0 && elevation > 0 && elevation < 80 &&
            alignment <= 5 && cameraHeight in 0.3..3.0 && roll <= 15
        // Compare with an Anchor in the current world frame, not yesterday's pose.
        val previous = lastCameraAnchor?.pose
        val moved = if (previous == null) true else {
            val x = camera.tx() - previous.tx(); val y = camera.ty() - previous.ty()
            val z = camera.tz() - previous.tz()
            sqrt(x * x + y * y + z * z) > 0.06f
        }
        val now = android.os.SystemClock.elapsedRealtime()
        if (!valid) {
            resetStability()
            stableSince = now
        } else if (moved || abs(elevation - lastElevation) > 1 || abs(distance - lastDistance) > 0.08) {
            stableSince = now
            lastCameraAnchor?.detach()
            lastCameraAnchor = session!!.createAnchor(camera)
            lastElevation = elevation; lastDistance = distance
        }
        val stable = valid && now - stableSince >= 800
        tell("3 of 3: Step back safely. Aim + at the treetop. " +
            "Distance: ${String.format(java.util.Locale.US, "%.1f", distance)} m | " +
            "Elevation: ${elevation.roundToInt()} degrees | " +
            (if (!valid) "Keep the phone upright and aim above the marked base."
            else if (!stable) "Hold still." else "Ready. Capture treetop."))
        if (doAction && stable) {
            val payload = trunkPayload ?: return
            frame.acquireCameraImage().use { image ->
                payload.put("species_image_base64", Base64.encodeToString(uprightJpeg(frame, image), Base64.NO_WRAP))
            }
            payload.put("height_observation", JSONObject()
                .put("source", "arcore_base_anchor").put("tracking", "tracking").put("stable", true)
                .put("horizontal_distance_m", distance).put("elevation_degrees", elevation)
                .put("camera_height_m", cameraHeight).put("alignment_degrees", alignment))
            complete(payload)
        }
    }

    private fun uprightJpeg(frame: Frame, image: Image): ByteArray {
        val axis = floatArrayOf(image.width * 0.4f, image.height * 0.5f,
            image.width * 0.6f, image.height * 0.5f)
        val screen = FloatArray(4)
        frame.transformCoordinates2d(Coordinates2d.IMAGE_PIXELS, axis, Coordinates2d.VIEW_NORMALIZED, screen)
        val rotation = ((Math.toDegrees(atan2((screen[3] - screen[1]).toDouble(),
            (screen[2] - screen[0]).toDouble())) / 90).roundToInt() * 90 + 360) % 360
        val bytes = jpeg(image)
        if (rotation == 0) return bytes
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height,
            Matrix().apply { postRotate(rotation.toFloat()) }, true)
        val output = ByteArrayOutputStream()
        rotated.compress(Bitmap.CompressFormat.JPEG, 90, output)
        if (rotated !== bitmap) rotated.recycle()
        bitmap.recycle()
        return output.toByteArray()
    }

    private fun complete(payload: JSONObject) {
        if (finishing) return
        finishing = true
        val file = File(cacheDir, "dbh_ar_capture.json")
        file.writeText(payload.toString())
        runOnUiThread {
            setResult(RESULT_OK, Intent().putExtra("capture_path", file.absolutePath))
            finish()
        }
    }

    private fun jpeg(image: Image): ByteArray {
        val width = image.width; val height = image.height
        val nv21 = ByteArray(width * height * 3 / 2)
        val yPlane = image.planes[0]; val uPlane = image.planes[1]; val vPlane = image.planes[2]
        for (y in 0 until height) for (x in 0 until width)
            nv21[y * width + x] = yPlane.buffer.get(y * yPlane.rowStride + x * yPlane.pixelStride)
        var index = width * height
        for (y in 0 until height / 2) for (x in 0 until width / 2) {
            nv21[index++] = vPlane.buffer.get(y * vPlane.rowStride + x * vPlane.pixelStride)
            nv21[index++] = uPlane.buffer.get(y * uPlane.rowStride + x * uPlane.pixelStride)
        }
        val output = ByteArrayOutputStream()
        YuvImage(nv21, ImageFormat.NV21, width, height, null)
            .compressToJpeg(Rect(0, 0, width, height), 90, output)
        return output.toByteArray()
    }

    companion object {
        private fun floats(values: FloatArray): FloatBuffer = ByteBuffer.allocateDirect(values.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(values); position(0) }
    }
}
