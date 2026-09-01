package io.pulseapp.pulse

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import kotlin.math.max

internal class PulseHapticEngine(private val context: Context) {
    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    fun play(effect: String, intensity: Double, sharpness: Double): Boolean {
        if (!vibrator.hasVibrator() || !hapticsEnabled()) return false
        val scale = intensity.coerceIn(.15, 1.0).toFloat()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && playComposition(effect, scale)) {
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val predefined = when (effect) {
                "soft" -> VibrationEffect.EFFECT_TICK
                "deep" -> VibrationEffect.EFFECT_HEAVY_CLICK
                "reply" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                else -> VibrationEffect.EFFECT_CLICK
            }
            vibrator.vibrate(VibrationEffect.createPredefined(predefined))
            return true
        }
        // A long legacy on/off pulse feels buzzy. Let Flutter use its
        // action-oriented system fallback instead.
        return false
    }

    private fun playComposition(effect: String, scale: Float): Boolean {
        val primitives = when (effect) {
            "soft" -> intArrayOf(VibrationEffect.Composition.PRIMITIVE_LOW_TICK)
            "deep" -> intArrayOf(VibrationEffect.Composition.PRIMITIVE_THUD)
            "reply" -> intArrayOf(
                VibrationEffect.Composition.PRIMITIVE_CLICK,
                VibrationEffect.Composition.PRIMITIVE_THUD,
            )
            else -> intArrayOf(VibrationEffect.Composition.PRIMITIVE_CLICK)
        }
        if (!vibrator.areAllPrimitivesSupported(*primitives)) return false
        val composition = VibrationEffect.startComposition()
        when (effect) {
            "reply" -> composition
                .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, max(.45f, scale * .75f))
                .addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, scale, 80)
            else -> composition.addPrimitive(primitives.first(), scale)
        }
        vibrator.vibrate(composition.compose())
        return true
    }

    private fun hapticsEnabled(): Boolean = runCatching {
        Settings.System.getInt(
            context.contentResolver,
            Settings.System.HAPTIC_FEEDBACK_ENABLED,
            1,
        ) == 1
    }.getOrDefault(true)
}
