package io.pulseapp.pulse

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import java.util.Random
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.sin

/** Seamless, low-volume procedural candle audio with no recorded speech. */
internal class CandleAudioEngine(private val context: Context) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val random = Random(0x50554c5345L)
    @Volatile private var running = false
    @Volatile private var style = 0
    @Volatile private var intensity = .5
    @Volatile private var turbulence = 0.0
    @Volatile private var ember = 0.0
    @Volatile private var sharedHeat = 0.0
    @Volatile private var cue = 0
    private var audioThread: Thread? = null
    private var audioTrack: AudioTrack? = null

    fun start(style: Int, intensity: Double) {
        this.style = style.coerceIn(0, 2)
        this.intensity = intensity.coerceIn(0.0, 1.0)
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        if (running) return
        running = true
        audioThread = Thread(::renderLoop, "PulseCandleAudio").apply {
            isDaemon = true
            start()
        }
    }

    fun ignite(style: Int) {
        start(style, .45)
        cue = 1
    }

    fun update(value: Double, turbulence: Double, ember: Double, sharedHeat: Double) {
        intensity = value.coerceIn(0.0, 1.0)
        this.turbulence = turbulence.coerceIn(0.0, 1.0)
        this.ember = ember.coerceIn(0.0, 1.0)
        this.sharedHeat = sharedHeat.coerceIn(0.0, 1.0)
    }

    fun extinguish() {
        if (!running) return
        cue = 2
        mainHandler.removeCallbacksAndMessages(this)
        mainHandler.postAtTime({ stop() }, this, android.os.SystemClock.uptimeMillis() + 850)
    }

    fun stop() {
        mainHandler.removeCallbacksAndMessages(this)
        running = false
        val thread = audioThread
        if (thread != null && thread !== Thread.currentThread()) {
            runCatching { thread.join(180) }
        }
        audioThread = null
        val track = audioTrack
        audioTrack = null
        runCatching { track?.pause() }
        runCatching { track?.flush() }
        runCatching { track?.release() }
    }

    private fun renderLoop() {
        val sampleRate = 22_050
        val minimum = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufferSize = max(minimum, 2048)
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        audioTrack = track
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            running = false
            track.release()
            return
        }
        val samples = ShortArray(256)
        var bed = 0.0
        var crackle = 0.0
        var phase = 0.0
        var cueSamples = 0
        var activeCue = 0
        track.play()
        while (running) {
            val currentCue = cue
            if (currentCue != 0) {
                cue = 0
                activeCue = currentCue
                cueSamples = if (currentCue == 1) sampleRate / 5 else sampleRate * 3 / 4
            }
            val styleCrackle = when (style) {
                0 -> .72
                1 -> .42
                else -> .28
            }
            for (index in samples.indices) {
                val noise = random.nextDouble() * 2 - 1
                bed = bed * .972 + noise * .028
                if (random.nextDouble() <
                    .00024 + styleCrackle * .00042 + turbulence * .00058) {
                    crackle += (.28 + random.nextDouble() * .72) * styleCrackle
                }
                crackle *= .932
                phase += 2 * PI * 43 / sampleRate
                val glassResonance = if (style == 1) sin(phase * 2.31) * .0018 else 0.0
                val togetherTone = sin(phase * 1.47) * .0019 * sharedHeat
                var value = bed * (.010 + turbulence * .014) +
                    crackle * (.038 + turbulence * .020) +
                    sin(phase) * .0015 + glassResonance + togetherTone +
                    noise * .012 * ember
                if (cueSamples > 0) {
                    val total = if (activeCue == 1) sampleRate / 5 else sampleRate * 3 / 4
                    val progress = 1.0 - cueSamples.toDouble() / total
                    value += if (activeCue == 1) {
                        noise * .055 * (1 - progress) + sin(phase * 7) * .018 * (1 - progress)
                    } else {
                        noise * .030 * sin(progress * PI)
                    }
                    cueSamples--
                }
                val gain = .20 + intensity * .28
                samples[index] = (value * gain * Short.MAX_VALUE)
                    .toInt()
                    .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                    .toShort()
            }
            if (track.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING) < 0) break
        }
        if (audioTrack === track) audioTrack = null
        runCatching { track.stop() }
        track.release()
    }
}
