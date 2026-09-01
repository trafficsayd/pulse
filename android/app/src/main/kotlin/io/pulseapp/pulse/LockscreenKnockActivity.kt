package io.pulseapp.pulse

import android.app.Activity
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import java.lang.ref.WeakReference
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

private const val KNOCK_CHANNEL = "pulse_lockscreen_knock"
private const val KNOCK_NOTIFICATION_ID = 7813
private const val KNOCK_WAKE_TAG = "pulse:knock-lock-screen"
private const val KNOCK_WAKE_MS = 8_000L
private const val KNOCK_COOLDOWN_MS = 30_000L

internal data class NativeKnock(
    val id: String,
    val seriesId: String,
    val x: Float,
    val y: Float,
    val intensity: Float,
    val sharpness: Float,
    val receivedAt: Long = SystemClock.elapsedRealtime(),
)

internal object LockscreenKnockController {
    private val lock = Any()
    private val hits = ArrayDeque<NativeKnock>()
    private val seen = LinkedHashSet<String>()
    private var activity = WeakReference<LockscreenKnockActivity>(null)
    private var lastSeriesId = "lockscreen"
    private var russian = true

    var replySink: ((Map<String, Any>) -> Unit)? = null

    fun handleEvent(
        context: Context,
        eventType: String,
        data: Map<*, *>,
        appResumed: Boolean,
        languageCode: String?,
    ) {
        russian = languageCode?.lowercase()?.startsWith("ru") != false
        if (eventType != "tap" && eventType != "knock_hit" && eventType != "knock_reply") return
        val hit = parse(eventType, data) ?: return
        synchronized(lock) {
            if (eventType != "tap" && !seen.add(hit.id)) return
            if (seen.size > 128) seen.remove(seen.first())
            hits.addLast(hit)
            while (hits.size > 16) hits.removeFirst()
            lastSeriesId = hit.seriesId
        }
        PulseHapticEngine(context).play(
            if (eventType == "knock_reply") "reply" else depth(hit.intensity),
            hit.intensity.toDouble(),
            hit.sharpness.toDouble(),
        )
        activity.get()?.refresh()

        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val protectedPresentation = !power.isInteractive || keyguard.isKeyguardLocked
        if (!appResumed || protectedPresentation) {
            LockscreenKnockNotifier.show(context)
            if (protectedPresentation) LockscreenKnockWakeController.wake(context)
        }
    }

    fun snapshot(): List<NativeKnock> = synchronized(lock) { hits.toList() }
    fun isRussian(): Boolean = russian
    fun attach(value: LockscreenKnockActivity) { activity = WeakReference(value) }
    fun detach(value: LockscreenKnockActivity) {
        if (activity.get() === value) activity.clear()
    }

    fun reply(x: Float, y: Float) {
        val series = lastSeriesId
        val id = UUID.randomUUID().toString()
        replySink?.invoke(
            mapOf(
                "v" to 2,
                "id" to id,
                "seriesId" to "reply-$id",
                "sequence" to 0,
                "x" to x.coerceIn(0f, 1f).toDouble(),
                "y" to y.coerceIn(0f, 1f).toDouble(),
                "relativeOffsetMs" to 0,
                "replyToSeriesId" to series,
                "character" to mapOf(
                    "intensity" to .58,
                    "sharpness" to .62,
                    "durationMs" to 82,
                    "contactClass" to "tip",
                    "confidence" to .35,
                ),
            ),
        )
    }

    fun dismiss(context: Context) {
        LockscreenKnockNotifier.cancel(context)
        activity.get()?.finish()
    }

    private fun parse(type: String, data: Map<*, *>): NativeKnock? {
        val x = (data["x"] as? Number)?.toFloat() ?: return null
        val y = (data["y"] as? Number)?.toFloat() ?: return null
        if (x !in 0f..1f || y !in 0f..1f) return null
        if (type == "tap") {
            return NativeKnock("legacy-${SystemClock.elapsedRealtime()}", "legacy", x, y, .5f, .58f)
        }
        if ((data["v"] as? Number)?.toInt() != 2) return null
        val id = data["id"] as? String ?: return null
        val seriesId = data["seriesId"] as? String ?: return null
        val character = data["character"] as? Map<*, *> ?: return null
        val intensity = (character["intensity"] as? Number)?.toFloat() ?: return null
        val sharpness = (character["sharpness"] as? Number)?.toFloat() ?: return null
        if (id.isBlank() || seriesId.isBlank() || intensity !in 0f..1f || sharpness !in 0f..1f) return null
        return NativeKnock(id, seriesId, x, y, intensity, sharpness)
    }

    private fun depth(intensity: Float) = when {
        intensity < .34f -> "soft"
        intensity < .68f -> "clear"
        else -> "deep"
    }
}

internal object LockscreenKnockWakeController {
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastWakeAt = 0L

    @Suppress("DEPRECATION")
    fun wake(context: Context) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastWakeAt < KNOCK_COOLDOWN_MS) return
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (power.isInteractive) return
        lastWakeAt = now
        runCatching {
            val lock = wakeLock ?: power.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                KNOCK_WAKE_TAG,
            ).also {
                it.setReferenceCounted(false)
                wakeLock = it
            }
            if (!lock.isHeld) lock.acquire(KNOCK_WAKE_MS)
        }
    }

    fun release() = runCatching { wakeLock?.takeIf { it.isHeld }?.release() }.let { Unit }
}

internal object LockscreenKnockNotifier {
    fun show(context: Context) {
        if (!LockscreenRayNotifier.notificationsEnabled(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)
        val intent = Intent(context, LockscreenKnockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = PendingIntent.getActivity(
            context,
            13,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, KNOCK_CHANNEL)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(context)
        }
        val russian = LockscreenKnockController.isRussian()
        builder
            .setSmallIcon(R.drawable.ic_pulse_notification)
            .setContentTitle(if (russian) "Близкий стучится к вам" else "Someone close is knocking")
            .setContentText(if (russian) "Коснитесь, чтобы ответить" else "Touch to answer")
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_HIGH)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setTimeoutAfter(30_000L)
            .setOnlyAlertOnce(false)
            .setFullScreenIntent(pending, true)
        manager.notify(KNOCK_NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(KNOCK_NOTIFICATION_ID)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val russian = LockscreenKnockController.isRussian()
        manager.createNotificationChannel(
            NotificationChannel(
                KNOCK_CHANNEL,
                if (russian) "Тук-Тук на экране блокировки" else "Lock-screen knocks",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
                enableLights(true)
            },
        )
    }
}

class LockscreenKnockActivity : Activity() {
    private lateinit var surface: KnockLockscreenView

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
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.rgb(10, 7, 18)
        surface = KnockLockscreenView(this)
        setContentView(surface)
        LockscreenKnockController.attach(this)
        LockscreenKnockNotifier.cancel(this)
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    override fun onDestroy() {
        LockscreenKnockController.detach(this)
        LockscreenKnockWakeController.release()
        super.onDestroy()
    }

    fun refresh() {
        if (!::surface.isInitialized) return
        surface.hits = LockscreenKnockController.snapshot()
        surface.invalidate()
    }

    override fun onBackPressed() = LockscreenKnockController.dismiss(this)
}

private class KnockLockscreenView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    var hits: List<NativeKnock> = LockscreenKnockController.snapshot()

    init {
        isClickable = true
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.shader = RadialGradient(
            width * .5f,
            height * .42f,
            max(width, height) * .75f,
            intArrayOf(Color.rgb(58, 25, 91), Color.rgb(18, 10, 31), Color.rgb(8, 6, 14)),
            floatArrayOf(0f, .55f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.shader = null

        val now = SystemClock.elapsedRealtime()
        hits.forEach { hit ->
            val age = ((now - hit.receivedAt) / 1400f).coerceIn(0f, 1f)
            val cx = hit.x * width
            val cy = hit.y * height
            val radius = (22f + 115f * age) * density * (.7f + hit.intensity * .45f)
            paint.style = Paint.Style.FILL
            paint.color = Color.argb(((1f - age) * 105).toInt(), 196, 123, 255)
            canvas.drawCircle(cx, cy, radius * .38f, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = max(1.5f, 4f * (1f - age)) * density
            paint.color = Color.argb(((1f - age) * 220).toInt(), 225, 190, 255)
            canvas.drawCircle(cx, cy, radius, paint)
        }

        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
        paint.textSize = 25f * density
        paint.color = Color.WHITE
        canvas.drawText(if (LockscreenKnockController.isRussian()) "Тук-Тук" else "Knock-Knock", width / 2f, 90f * density, paint)
        paint.typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
        paint.textSize = 15f * density
        paint.color = Color.rgb(221, 204, 237)
        canvas.drawText(
            if (LockscreenKnockController.isRussian()) "Коснитесь поверхности, чтобы ответить" else "Touch the surface to answer",
            width / 2f,
            height - 64f * density,
            paint,
        )
        paint.textAlign = Paint.Align.RIGHT
        paint.textSize = 28f * density
        paint.color = Color.argb(210, 255, 255, 255)
        canvas.drawText("×", width - 24f * density, 54f * density, paint)
        if (hits.any { now - it.receivedAt < 1450L }) postInvalidateOnAnimation()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action != MotionEvent.ACTION_UP) return true
        if (event.x > width - 72f * density && event.y < 86f * density) {
            LockscreenKnockController.dismiss(context)
            return true
        }
        val x = (event.x / width).coerceIn(0f, 1f)
        val y = (event.y / height).coerceIn(0f, 1f)
        LockscreenKnockController.reply(x, y)
        PulseHapticEngine(context).play("reply", .58, .62)
        hits = hits + NativeKnock(UUID.randomUUID().toString(), "local", x, y, .58f, .62f)
        invalidate()
        return true
    }
}
