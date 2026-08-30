package io.pulseapp.pulse

import android.app.Activity
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sin

private const val LOCKSCREEN_NOTIFICATION_CHANNEL = "pulse_lockscreen_ray"
private const val LOCKSCREEN_NOTIFICATION_ID = 7319
private const val LOCKSCREEN_WAKE_TIMEOUT_MS = 15_000L
private const val LOCKSCREEN_WAKE_TAG = "pulse:ray-lock-screen"

internal data class NormalizedPoint(
    val x: Float,
    val y: Float,
    val pressure: Float = 1f,
    val elapsedMs: Int = 0,
)

internal data class NativeRayStroke(
    val id: String,
    val points: MutableList<NormalizedPoint>,
    val color: Int,
    val width: Float,
    val effect: Int,
    var complete: Boolean = false,
)

internal data class NativeRaySnapshot(
    val canvasColor: Int,
    val strokes: List<NativeRayStroke>,
    val activeStrokes: List<NativeRayStroke>,
    val receivingLive: Boolean,
)

/**
 * Process-local state shared by the Flutter bridge and the isolated
 * lock-screen activity. Incoming cards are replayed after a transport
 * reconnect, so rebuilding this state after process death is supported.
 */
internal object LockscreenRayController {
    private val stateLock = Any()
    private val strokes = mutableListOf<NativeRayStroke>()
    private val activeStrokes = linkedMapOf<String, NativeRayStroke>()
    private var legacyStrokeId: String? = null
    private var canvasColor: Int = Color.rgb(18, 13, 29)
    private var receivingLive = false
    private var languageCode = "en"
    private var activity = WeakReference<LockscreenRayActivity>(null)
    private var activityVisible = false

    fun handleEvent(
        context: Context,
        eventType: String,
        data: Map<*, *>,
        appResumed: Boolean,
        languageCode: String?,
    ) {
        synchronized(stateLock) {
            if (!languageCode.isNullOrBlank()) this.languageCode = languageCode
            when (eventType) {
                "ray_stroke_begin" -> beginStroke(data)
                "ray_stroke_points" -> appendPoints(data)
                "ray_stroke_end" -> finishStrokeV2(data)
                "ray_state" -> applyCard(data)
                "ray_undo" -> undoStroke(data)
                "ray_point" -> appendLegacyPoint(data)
                "ray_end" -> finishLegacyStroke()
                "ray_clear" -> {
                    strokes.clear()
                    activeStrokes.clear()
                    legacyStrokeId = null
                    receivingLive = true
                }
                "ray_canvas" -> number(data["color"])?.let { canvasColor = it.toInt() }
                "ray_card" -> applyCard(data)
                else -> return
            }
        }

        val currentActivity = activity.get()
        currentActivity?.refreshSnapshot()

        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val locked = keyguard.isKeyguardLocked
        val screenOff = !power.isInteractive
        if (locked || screenOff) {
            // Do this even if Android has not delivered onPause yet: there is
            // a short race after the power button where the Activity can
            // still be marked visible while the display is already dark.
            if (screenOff) LockscreenRayWakeController.wakeForIncoming(context)
            if (currentActivity == null || !activityVisible) {
                // A dark display is not necessarily reported as a locked
                // keyguard (for example during the lock-after-screen-timeout
                // grace period). Wake it explicitly before requesting the
                // keyguard-safe Activity, otherwise the first live points can
                // arrive while the phone remains completely black.
                LockscreenRayNotifier.show(
                    context,
                    eventType == "ray_card" ||
                        eventType == "ray_end" ||
                        eventType == "ray_stroke_end" ||
                        eventType == "ray_state",
                )
                showActivity(context)
            }
        } else if (
            !appResumed &&
            (eventType == "ray_card" ||
                eventType == "ray_end" ||
                eventType == "ray_stroke_end" ||
                eventType == "ray_state")
        ) {
            LockscreenRayNotifier.show(context, includePreview = true)
        }
    }

    private fun beginStroke(data: Map<*, *>) {
        val raw = data["stroke"] as? Map<*, *> ?: return
        val stroke = parseStroke(raw, complete = false) ?: return
        activeStrokes[stroke.id] = stroke
        receivingLive = true
    }

    private fun appendPoints(data: Map<*, *>) {
        val id = (data["id"] as? String)?.take(120) ?: return
        val stroke = activeStrokes[id] ?: return
        val rawPoints = data["points"] as? List<*> ?: return
        for (raw in rawPoints.take(32)) {
            val point = parsePoint(raw) ?: continue
            if (stroke.points.size >= 240) break
            val previous = stroke.points.lastOrNull()
            if (previous != null &&
                kotlin.math.abs(previous.x - point.x) < 0.0004f &&
                kotlin.math.abs(previous.y - point.y) < 0.0004f
            ) {
                continue
            }
            stroke.points.add(point)
        }
        receivingLive = activeStrokes.isNotEmpty()
    }

    private fun finishStrokeV2(data: Map<*, *>) {
        val raw = data["stroke"] as? Map<*, *> ?: return
        val complete = parseStroke(raw, complete = true) ?: return
        activeStrokes.remove(complete.id)
        strokes.removeAll { it.id == complete.id }
        strokes.add(complete)
        while (strokes.size > 64) strokes.removeAt(0)
        receivingLive = activeStrokes.isNotEmpty()
    }

    private fun undoStroke(data: Map<*, *>) {
        val id = (data["id"] as? String)?.take(120) ?: return
        activeStrokes.remove(id)
        strokes.removeAll { it.id == id }
        receivingLive = activeStrokes.isNotEmpty()
    }

    private fun appendLegacyPoint(data: Map<*, *>) {
        val x = number(data["x"])?.toFloat()?.coerceIn(0f, 1f) ?: return
        val y = number(data["y"])?.toFloat()?.coerceIn(0f, 1f) ?: return
        val color = number(data["color"])?.toInt() ?: Color.rgb(151, 71, 255)
        val width = number(data["width"])?.toFloat()?.coerceIn(1f, 32f) ?: 10f
        val effect = number(data["effect"])?.toInt()?.coerceIn(0, 4) ?: 1
        var id = legacyStrokeId
        var current = id?.let(activeStrokes::get)
        if (current == null) {
            id = "legacy-${System.nanoTime()}"
            legacyStrokeId = id
            current = NativeRayStroke(id, mutableListOf(), color, width, effect)
            activeStrokes[id] = current
        }
        current.points.add(NormalizedPoint(x, y))
        receivingLive = true
    }

    private fun finishLegacyStroke() {
        val id = legacyStrokeId
        val complete = id?.let(activeStrokes::remove)
        if (complete != null && complete.points.isNotEmpty()) {
            complete.complete = true
            strokes.add(complete)
        }
        legacyStrokeId = null
        receivingLive = activeStrokes.isNotEmpty()
    }

    private fun applyCard(data: Map<*, *>) {
        strokes.clear()
        activeStrokes.clear()
        legacyStrokeId = null
        number(data["canvas"])?.let { canvasColor = it.toInt() }
        val rawStrokes = data["strokes"] as? List<*> ?: emptyList<Any>()
        for (rawStroke in rawStrokes.take(64)) {
            val map = rawStroke as? Map<*, *> ?: continue
            parseStroke(map, complete = true)?.let(strokes::add)
        }
        receivingLive = false
    }

    private fun parseStroke(map: Map<*, *>, complete: Boolean): NativeRayStroke? {
        val rawPoints = map["points"] as? List<*> ?: return null
        val points = mutableListOf<NormalizedPoint>()
        for (rawPoint in rawPoints.take(240)) {
            parsePoint(rawPoint)?.let(points::add)
        }
        if (points.isEmpty()) return null
        return NativeRayStroke(
            id = ((map["id"] as? String)?.take(120)).orEmpty().ifEmpty {
                "card-${System.nanoTime()}-${strokes.size}"
            },
            points = points,
            color = number(map["color"])?.toInt() ?: Color.rgb(151, 71, 255),
            width = number(map["width"])?.toFloat()?.coerceIn(1f, 32f) ?: 10f,
            effect = number(map["effect"])?.toInt()?.coerceIn(0, 4) ?: 1,
            complete = complete || map["complete"] == true,
        )
    }

    private fun parsePoint(rawPoint: Any?): NormalizedPoint? {
        val pair = rawPoint as? List<*> ?: return null
        if (pair.size < 2) return null
        val x = number(pair[0])?.toFloat()?.coerceIn(0f, 1f) ?: return null
        val y = number(pair[1])?.toFloat()?.coerceIn(0f, 1f) ?: return null
        val pressure = number(pair.getOrNull(2))?.toFloat()?.coerceIn(0.12f, 1.8f) ?: 1f
        val elapsed = number(pair.getOrNull(3))?.toInt()?.coerceIn(0, 600_000) ?: 0
        return NormalizedPoint(x, y, pressure, elapsed)
    }

    private fun number(value: Any?): Number? = value as? Number

    fun snapshot(): NativeRaySnapshot = synchronized(stateLock) {
        NativeRaySnapshot(
            canvasColor = canvasColor,
            strokes = strokes.map(::copyStroke),
            activeStrokes = activeStrokes.values.map(::copyStroke),
            receivingLive = receivingLive,
        )
    }

    fun isRussian(): Boolean = synchronized(stateLock) { languageCode == "ru" }

    private fun copyStroke(stroke: NativeRayStroke) = NativeRayStroke(
        id = stroke.id,
        points = stroke.points.toMutableList(),
        color = stroke.color,
        width = stroke.width,
        effect = stroke.effect,
        complete = stroke.complete,
    )

    fun attach(value: LockscreenRayActivity) {
        activity = WeakReference(value)
    }

    fun setVisible(value: LockscreenRayActivity, visible: Boolean) {
        if (activity.get() === value) activityVisible = visible
    }

    fun detach(value: LockscreenRayActivity) {
        if (activity.get() === value) {
            activityVisible = false
            activity.clear()
        }
    }

    fun dismiss(context: Context) {
        synchronized(stateLock) {
            strokes.clear()
            activeStrokes.clear()
            legacyStrokeId = null
            receivingLive = false
        }
        LockscreenRayNotifier.cancel(context)
        activity.get()?.finish()
    }

    private fun showActivity(context: Context) {
        val intent = Intent(context, LockscreenRayActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION,
            )
        }
        runCatching { context.startActivity(intent) }
    }
}

/**
 * Short, bounded display wake-up used only for an incoming Ray interaction.
 *
 * [Activity.setTurnScreenOn] remains the primary API. The wake lock closes
 * the gap before Android creates the full-screen Activity and also covers
 * OEMs that delay full-screen notification delivery while the display is
 * fully off. It expires automatically even if an OEM refuses the launch.
 */
internal object LockscreenRayWakeController {
    private var wakeLock: PowerManager.WakeLock? = null

    @Suppress("DEPRECATION")
    fun wakeForIncoming(context: Context) {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (power.isInteractive) return
        synchronized(this) {
            runCatching {
                val lock = wakeLock ?: power.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    LOCKSCREEN_WAKE_TAG,
                ).also {
                    it.setReferenceCounted(false)
                    wakeLock = it
                }
                if (!lock.isHeld) lock.acquire(LOCKSCREEN_WAKE_TIMEOUT_MS)
            }
        }
    }

    fun release() {
        synchronized(this) {
            runCatching {
                wakeLock?.takeIf { it.isHeld }?.release()
            }
        }
    }
}

/** Store-safe fallback when an OEM blocks background activity launches. */
internal object LockscreenRayNotifier {
    fun notificationsEnabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val runtimeGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        return runtimeGranted && manager.areNotificationsEnabled()
    }

    fun fullScreenIntentEnabled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.canUseFullScreenIntent()
    }

    fun presentationReady(context: Context): Boolean =
        notificationsEnabled(context) && fullScreenIntentEnabled(context)

    fun show(context: Context, includePreview: Boolean) {
        if (!notificationsEnabled(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager, context)
        val russian = LockscreenRayController.isRussian()
        val intent = Intent(context, LockscreenRayActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, LOCKSCREEN_NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_pulse_notification)
            .setContentTitle(if (russian) "Рисунок от близкого" else "A drawing from someone close")
            .setContentText(if (russian) "Нажмите, чтобы почувствовать момент" else "Tap to share the moment")
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setTimeoutAfter(30_000L)
            .setOnlyAlertOnce(!includePreview)
            .setFullScreenIntent(pending, true)

        if (includePreview) {
            val preview = RayRenderer.renderBitmap(LockscreenRayController.snapshot(), 720, 720)
            builder.setStyle(Notification.BigPictureStyle().bigPicture(preview).bigLargeIcon(null as Bitmap?))
        }
        manager.notify(LOCKSCREEN_NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(LOCKSCREEN_NOTIFICATION_ID)
    }

    private fun ensureChannel(manager: NotificationManager, context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val russian = LockscreenRayController.isRussian()
        val channel = NotificationChannel(
            LOCKSCREEN_NOTIFICATION_CHANNEL,
            if (russian) "Рисунки на экране блокировки" else "Lock-screen drawings",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = if (russian) {
                "Показывает рисунки от близких, даже когда телефон заблокирован"
            } else {
                "Shows drawings from close people while the phone is locked"
            }
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            enableLights(true)
        }
        manager.createNotificationChannel(channel)
    }

}

class LockscreenRayActivity : Activity() {
    private lateinit var rayView: RayLockscreenView
    private lateinit var statusText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
        )
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.BLACK
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        setContentView(buildContent())
        LockscreenRayController.attach(this)
        refreshSnapshot()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        refreshSnapshot()
    }

    override fun onResume() {
        super.onResume()
        LockscreenRayWakeController.wakeForIncoming(this)
        LockscreenRayController.attach(this)
        LockscreenRayController.setVisible(this, true)
        LockscreenRayNotifier.cancel(this)
        refreshSnapshot()
    }

    override fun onPause() {
        LockscreenRayController.setVisible(this, false)
        super.onPause()
    }

    override fun onDestroy() {
        LockscreenRayController.detach(this)
        LockscreenRayWakeController.release()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        LockscreenRayController.dismiss(this)
    }

    fun refreshSnapshot() {
        if (!::rayView.isInitialized) return
        val snapshot = LockscreenRayController.snapshot()
        rayView.snapshot = snapshot
        statusText.text = if (snapshot.receivingLive) {
            if (isRussian()) "РИСУЕТ СЕЙЧАС" else "DRAWING NOW"
        } else {
            if (isRussian()) "РИСУНОК ДЛЯ ВАС" else "A DRAWING FOR YOU"
        }
        rayView.invalidate()
    }

    private fun buildContent(): View {
        val root = FrameLayout(this)
        rayView = RayLockscreenView(this)
        root.addView(
            rayView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(28), dp(58), dp(88), dp(12))
        }
        header.addView(TextView(this).apply {
            text = "Pulse"
            setTextColor(Color.WHITE)
            textSize = 25f
            typeface = Typeface.DEFAULT_BOLD
        })
        header.addView(TextView(this).apply {
            text = if (isRussian()) "Рисунок от близкого человека" else "A drawing from someone close"
            setTextColor(Color.argb(184, 233, 221, 255))
            textSize = 14f
            setPadding(0, dp(4), 0, 0)
        })
        root.addView(
            header,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            ),
        )

        val close = TextView(this).apply {
            text = "×"
            textSize = 32f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            contentDescription = if (isRussian()) "Закрыть рисунок" else "Close drawing"
            isClickable = true
            isFocusable = true
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(92, 255, 255, 255))
                setStroke(dp(1), Color.argb(90, 255, 255, 255))
            }
            setOnClickListener { LockscreenRayController.dismiss(this@LockscreenRayActivity) }
        }
        root.addView(
            close,
            FrameLayout.LayoutParams(dp(52), dp(52), Gravity.TOP or Gravity.END).apply {
                topMargin = dp(52)
                marginEnd = dp(24)
            },
        )

        statusText = TextView(this).apply {
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.10f
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.argb(118, 84, 35, 142))
                setStroke(dp(1), Color.argb(150, 151, 71, 255))
            }
        }
        root.addView(
            statusText,
            FrameLayout.LayoutParams(dp(214), dp(48), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
                bottomMargin = dp(52)
            },
        )
        return root
    }

    private fun isRussian(): Boolean {
        return LockscreenRayController.isRussian()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}

private class RayLockscreenView(context: Context) : View(context) {
    var snapshot: NativeRaySnapshot = LockscreenRayController.snapshot()

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        contentDescription = "Pulse Ray lock screen canvas"
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        RayRenderer.draw(canvas, width, height, snapshot)
        if (snapshot.strokes.isNotEmpty() || snapshot.activeStrokes.isNotEmpty()) {
            postInvalidateDelayed(50L)
        }
    }
}

private object RayRenderer {
    fun renderBitmap(snapshot: NativeRaySnapshot, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        draw(Canvas(bitmap), width, height, snapshot)
        return bitmap
    }

    fun draw(canvas: Canvas, width: Int, height: Int, snapshot: NativeRaySnapshot) {
        val background = Paint().apply {
            shader = LinearGradient(
                0f,
                0f,
                width.toFloat(),
                height.toFloat(),
                intArrayOf(Color.rgb(10, 8, 18), snapshot.canvasColor, Color.rgb(20, 10, 36)),
                null,
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), background)

        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = max(1f, width / 720f)
            color = Color.argb(34, 151, 71, 255)
        }
        val centerX = width / 2f
        val centerY = height / 2f
        val baseRadius = width * 0.15f
        repeat(5) { index ->
            canvas.drawCircle(centerX, centerY, baseRadius + index * width * 0.095f, ring)
        }

        for (stroke in snapshot.strokes) drawStroke(canvas, width, height, stroke)
        for (stroke in snapshot.activeStrokes) {
            drawStroke(canvas, width, height, stroke)
            drawPresence(canvas, width, height, stroke)
        }
    }

    private fun drawStroke(canvas: Canvas, width: Int, height: Int, stroke: NativeRayStroke) {
        if (stroke.points.isEmpty()) return
        val path = smoothPath(stroke, width, height)
        val first = stroke.points.first()
        val scaledWidth = (stroke.width * width / 360f).coerceAtLeast(2f)
        val phase = SystemClock.uptimeMillis() / 1000f * 2f
        val breathing = 0.88f + ((sin(phase + stroke.id.hashCode() * 0.001f) + 1f) * 0.06f)

        when (stroke.effect) {
            1 -> {
                canvas.drawPath(
                    path,
                    strokePaint(
                        withAlpha(stroke.color, (52 * breathing).toInt()),
                        scaledWidth * 4.6f,
                        scaledWidth * 1.35f,
                    ),
                )
                canvas.drawPath(
                    path,
                    strokePaint(withAlpha(stroke.color, 88), scaledWidth * 2.15f),
                )
            }
            2 -> canvas.drawPath(
                path,
                strokePaint(
                    withAlpha(stroke.color, (56 * breathing).toInt()),
                    scaledWidth * 3.25f,
                    scaledWidth,
                ),
            )
            3 -> {
                canvas.save()
                canvas.translate(0.8f, -0.6f)
                canvas.drawPath(path, strokePaint(withAlpha(stroke.color, 34), scaledWidth * 2.7f))
                canvas.restore()
                canvas.save()
                canvas.translate(-0.7f, 0.9f)
                canvas.drawPath(path, strokePaint(withAlpha(stroke.color, 44), scaledWidth * 1.8f))
                canvas.restore()
            }
        }

        if (stroke.points.size == 1) {
            canvas.drawCircle(
                first.x * width,
                first.y * height,
                scaledWidth * first.pressure.coerceIn(0.4f, 1.4f) / 2f,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = stroke.color },
            )
        } else {
            drawPressureSegments(canvas, width, height, stroke, scaledWidth)
        }
        if (stroke.effect == 4) {
            drawSparkles(canvas, width, height, stroke, scaledWidth, phase)
        }
    }

    private fun smoothPath(stroke: NativeRayStroke, width: Int, height: Int): Path {
        val path = Path()
        val points = stroke.points
        val first = points.first()
        path.moveTo(first.x * width, first.y * height)
        if (points.size == 1) return path
        for (index in 1 until points.lastIndex) {
            val point = points[index]
            val next = points[index + 1]
            path.quadTo(
                point.x * width,
                point.y * height,
                (point.x + next.x) * width / 2f,
                (point.y + next.y) * height / 2f,
            )
        }
        val last = points.last()
        path.lineTo(last.x * width, last.y * height)
        return path
    }

    private fun drawPressureSegments(
        canvas: Canvas,
        width: Int,
        height: Int,
        stroke: NativeRayStroke,
        baseWidth: Float,
    ) {
        for (index in 1 until stroke.points.size) {
            val a = stroke.points[index - 1]
            val b = stroke.points[index]
            val ax = a.x * width
            val ay = a.y * height
            val bx = b.x * width
            val by = b.y * height
            val elapsed = max(1, b.elapsedMs - a.elapsedMs)
            val speed = hypot(bx - ax, by - ay) / elapsed
            val speedFactor = (1.08f - speed * 0.22f).coerceIn(0.72f, 1.08f)
            val pressure = ((a.pressure + b.pressure) / 2f).coerceIn(0.2f, 1.5f)
            val pressureFactor = (0.58f + pressure * 0.52f).coerceIn(0.62f, 1.28f)
            val segmentWidth = baseWidth * speedFactor * pressureFactor
            val segment = Path().apply {
                moveTo(ax, ay)
                lineTo(bx, by)
            }
            canvas.drawPath(
                segment,
                strokePaint(
                    withAlpha(stroke.color, if (stroke.effect == 3) 148 else 240),
                    segmentWidth,
                ),
            )
        }
        val last = stroke.points.last()
        canvas.drawCircle(
            last.x * width,
            last.y * height,
            baseWidth * last.pressure.coerceIn(0.4f, 1.4f) / 2f,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = withAlpha(stroke.color, 240) },
        )
    }

    private fun drawSparkles(
        canvas: Canvas,
        width: Int,
        height: Int,
        stroke: NativeRayStroke,
        baseWidth: Float,
        phase: Float,
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        for (index in stroke.points.indices step 6) {
            val point = stroke.points[index]
            val twinkle = (sin(phase * 1.6f + index + stroke.id.hashCode() * 0.001f) + 1f) / 2f
            val radius = baseWidth * (0.12f + twinkle * 0.18f) + 0.8f
            val direction = if (index % 2 == 0) 1f else -1f
            val cx = point.x * width + baseWidth * direction
            val cy = point.y * height - baseWidth * 0.72f
            paint.color = withAlpha(stroke.color, (118 + twinkle * 118).toInt())
            canvas.drawCircle(cx, cy, radius, paint)
            paint.strokeWidth = 0.7f
            canvas.drawLine(cx - radius * 2.2f, cy, cx + radius * 2.2f, cy, paint)
            canvas.drawLine(cx, cy - radius * 2.2f, cx, cy + radius * 2.2f, paint)
        }
    }

    private fun drawPresence(
        canvas: Canvas,
        width: Int,
        height: Int,
        stroke: NativeRayStroke,
    ) {
        val point = stroke.points.lastOrNull() ?: return
        val scaledWidth = (stroke.width * width / 360f).coerceAtLeast(2f)
        val phase = SystemClock.uptimeMillis() / 1000f * 2.7f
        val pulse = (sin(phase) + 1f) / 2f
        canvas.drawCircle(
            point.x * width,
            point.y * height,
            scaledWidth * 1.3f + pulse * 5f,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 1.2f
                color = withAlpha(stroke.color, (82 + pulse * 72).toInt())
            },
        )
        canvas.drawCircle(
            point.x * width,
            point.y * height,
            scaledWidth * 0.22f + 1.3f,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(220, 255, 255, 255) },
        )
    }

    private fun strokePaint(colorValue: Int, width: Float, blur: Float? = null) =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colorValue
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            strokeWidth = width
            if (blur != null) {
                maskFilter = BlurMaskFilter(blur.coerceIn(1f, 22f), BlurMaskFilter.Blur.NORMAL)
            }
        }

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
