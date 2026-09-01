package io.pulseapp.pulse

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.UUID

/** ADB-only entry point compiled exclusively into debug builds. */
class KnockDebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "io.pulseapp.pulse.DEBUG_KNOCK") return
        val id = UUID.randomUUID().toString()
        LockscreenKnockController.handleEvent(
            context = context,
            eventType = "knock_hit",
            data = mapOf(
                "v" to 2,
                "id" to id,
                "seriesId" to "adb-$id",
                "sequence" to 0,
                "x" to intent.getFloatExtra("x", .5f).toDouble(),
                "y" to intent.getFloatExtra("y", .48f).toDouble(),
                "relativeOffsetMs" to 0,
                "character" to mapOf(
                    "intensity" to intent.getFloatExtra("intensity", .65f).toDouble(),
                    "sharpness" to .62,
                    "durationMs" to 84,
                    "contactClass" to "tip",
                    "confidence" to .8,
                ),
            ),
            appResumed = false,
            languageCode = "ru",
        )
    }
}
