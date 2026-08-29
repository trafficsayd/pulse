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
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference
import kotlin.math.max

private const val LOCKSCREEN_NOTIFICATION_CHANNEL = "pulse_lockscreen_ray"
private const val LOCKSCREEN_NOTIFICATION_ID = 7319

internal data class NormalizedPoint(val x: Float, val y: Float)

internal data class NativeRayStroke(
    val points: MutableList<NormalizedPoint>,
    val color: Int,
    val width: Float,
    val effect: Int,
)

internal data class NativeRaySnapshot(
    val canvasColor: Int,
    val strokes: List<NativeRayStroke>,
    val activeStroke: NativeRayStroke?,
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
    private var activeStroke: NativeRayStroke? = null
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
                "ray_point" -> appendPoint(data)
                "ray_end" -> finishStroke()
                "ray_clear" -> {
                    strokes.clear()
                    activeStroke = null
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
        val locked = keyguard.isKeyguardLocked
        if (locked) {
            if (currentActivity == null || !activityVisible) {
                LockscreenRayNotifier.show(
                    context,
                    eventType == "ray_card" || eventType == "ray_end",
                )
                showActivity(context)
            }
        } else if (!appResumed && (eventType == "ray_card" || eventType == "ray_end")) {
            LockscreenRayNotifier.show(context, includePreview = true)
        }
    }

    private fun appendPoint(data: Map<*, *>) {
        val x = number(data["x"])?.toFloat()?.coerceIn(0f, 1f) ?: return
        val y = number(data["y"])?.toFloat()?.coerceIn(0f, 1f) ?: return
        val color = number(data["color"])?.toInt() ?: Color.rgb(151, 71, 255)
        val width = number(data["width"])?.toFloat()?.coerceIn(1f, 32f) ?: 10f
        val effect = number(data["effect"])?.toInt()?.coerceIn(0, 4) ?: 1
        var current = activeStroke
        if (current == null) {
            current = NativeRayStroke(mutableListOf(), color, width, effect)
            activeStroke = current
        }
        current.points.add(NormalizedPoint(x, y))
        receivingLive = true
    }

    private fun finishStroke() {
        activeStroke?.let { if (it.points.isNotEmpty()) strokes.add(it) }
        activeStroke = null
        receivingLive = false
    }

    private fun applyCard(data: Map<*, *>) {
        strokes.clear()
        activeStroke = null
        number(data["canvas"])?.let { canvasColor = it.toInt() }
        val rawStrokes = data["strokes"] as? List<*> ?: emptyList<Any>()
        for (rawStroke in rawStrokes.take(16)) {
            val map = rawStroke as? Map<*, *> ?: continue
            val rawPoints = map["points"] as? List<*> ?: continue
            val points = mutableListOf<NormalizedPoint>()
            for (rawPoint in rawPoints.take(80)) {
                val pair = rawPoint as? List<*> ?: continue
                if (pair.size < 2) continue
                val x = number(pair[0])?.toFloat()?.coerceIn(0f, 1f) ?: continue
                val y = number(pair[1])?.toFloat()?.coerceIn(0f, 1f) ?: continue
                points.add(NormalizedPoint(x, y))
            }
            if (points.isEmpty()) continue
            strokes.add(
                NativeRayStroke(
                    points = points,
                    color = number(map["color"])?.toInt() ?: Color.rgb(151, 71, 255),
                    width = number(map["width"])?.toFloat()?.coerceIn(1f, 32f) ?: 10f,
                    effect = number(map["effect"])?.toInt()?.coerceIn(0, 4) ?: 1,
                ),
            )
        }
        receivingLive = false
    }

    private fun number(value: Any?): Number? = value as? Number

    fun snapshot(): NativeRaySnapshot = synchronized(stateLock) {
        NativeRaySnapshot(
            canvasColor = canvasColor,
            strokes = strokes.map(::copyStroke),
            activeStroke = activeStroke?.let(::copyStroke),
            receivingLive = receivingLive,
        )
    }

    fun isRussian(): Boolean = synchronized(stateLock) { languageCode == "ru" }

    private fun copyStroke(stroke: NativeRayStroke) = NativeRayStroke(
        points = stroke.points.toMutableList(),
        color = stroke.color,
        width = stroke.width,
        effect = stroke.effect,
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
            activeStroke = null
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

/** Store-safe fallback when an OEM blocks background activity launches. */
internal object LockscreenRayNotifier {
    fun notificationsEnabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val runtimeGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        return runtimeGranted && manager.areNotificationsEnabled()
    }

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
            .setContentIntent(pending)
            .setAutoCancel(true)
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
        window.addFlags(WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON)
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
        snapshot.activeStroke?.let { drawStroke(canvas, width, height, it) }
    }

    private fun drawStroke(canvas: Canvas, width: Int, height: Int, stroke: NativeRayStroke) {
        if (stroke.points.isEmpty()) return
        val path = Path()
        val first = stroke.points.first()
        path.moveTo(first.x * width, first.y * height)
        for (point in stroke.points.drop(1)) path.lineTo(point.x * width, point.y * height)
        val scaledWidth = (stroke.width * width / 360f).coerceAtLeast(2f)

        if (stroke.effect in 1..3) {
            val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = withAlpha(stroke.color, if (stroke.effect == 1) 90 else 62)
                style = Paint.Style.STROKE
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
                strokeWidth = scaledWidth * if (stroke.effect == 1) 3.4f else 2.5f
                setShadowLayer(scaledWidth * 1.5f, 0f, 0f, stroke.color)
            }
            canvas.drawPath(path, glow)
        }

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = stroke.color
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            strokeWidth = scaledWidth
        }
        if (stroke.points.size == 1) {
            canvas.drawCircle(first.x * width, first.y * height, scaledWidth / 2f, paint)
        } else {
            canvas.drawPath(path, paint)
        }
    }

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
