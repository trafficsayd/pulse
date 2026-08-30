package io.pulseapp.pulse

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color

/** Debug-only adb hook for deterministic dark-screen Ray QA. */
class LockscreenRayDebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getStringExtra("type") ?: "ray_card") {
            "dismiss" -> LockscreenRayController.dismiss(context)
            "ray_point" -> LockscreenRayController.handleEvent(
                context = context,
                eventType = "ray_point",
                data = mapOf(
                    "x" to intent.getFloatExtra("x", 0.5f),
                    "y" to intent.getFloatExtra("y", 0.5f),
                    "color" to Color.rgb(151, 71, 255),
                    "width" to 12f,
                    "effect" to 1,
                ),
                appResumed = false,
                languageCode = "ru",
            )
            else -> LockscreenRayController.handleEvent(
                context = context,
                eventType = "ray_card",
                data = mapOf(
                    "canvas" to Color.rgb(18, 13, 29),
                    "strokes" to listOf(
                        mapOf(
                            "color" to Color.rgb(151, 71, 255),
                            "width" to 12f,
                            "effect" to 1,
                            "points" to listOf(
                                listOf(0.18f, 0.58f),
                                listOf(0.34f, 0.40f),
                                listOf(0.50f, 0.58f),
                                listOf(0.66f, 0.40f),
                                listOf(0.82f, 0.58f),
                            ),
                        ),
                    ),
                ),
                appResumed = false,
                languageCode = "ru",
            )
        }
    }
}
