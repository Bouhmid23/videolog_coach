package com.opkodelabs.videolog_coach

import android.Manifest
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "videolog/pip"
        const val BEEP_CHANNEL = "videolog/beep"
        const val MIC_METER_CHANNEL = "videolog/mic_meter"
        val DEFAULT_RATIO = Rational(9, 16)
    }

    private var pipChannel: MethodChannel? = null
    private var pipEnabled = false
    private var pipAspectRatio = DEFAULT_RATIO

    @Volatile
    private var micMeterRunning = false
    @Volatile
    private var currentMicLevel = 0.0
    private var micMeterThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Petit bip à l'arrivée d'un message du coach pour les lunettes.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BEEP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "beep") {
                    result.success(playBeep())
                } else {
                    result.notImplemented()
                }
            }

        // Jauge niveau microphone pour l'écran de pré-connexion.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MIC_METER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(startMicMeter())
                    "stop" -> {
                        stopMicMeter()
                        result.success(true)
                    }
                    "getLevel" -> result.success(currentMicLevel)
                    else -> result.notImplemented()
                }
            }

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(supportsPip())
                "enableAutoEnter" -> {
                    val width = call.argument<Int>("width") ?: 9
                    val height = call.argument<Int>("height") ?: 16
                    pipAspectRatio = safeRatio(width, height)
                    pipEnabled = true
                    updatePipParams()
                    result.success(true)
                }
                "disableAutoEnter" -> {
                    pipEnabled = false
                    updatePipParams()
                    result.success(true)
                }
                "enter" -> {
                    // Entrée manuelle : ne modifie pas pipEnabled (auto-enter).
                    result.success(enterPip())
                }
                "isInPip" -> result.success(isInPipMode())
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopMicMeter()
        super.onDestroy()
    }

    @Synchronized
    private fun startMicMeter(): Boolean {
        if (micMeterRunning) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val sampleRate = 16000
        val minBuffer = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) return false

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuffer * 2,
            )
        } catch (e: Throwable) {
            return false
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            try {
                record.release()
            } catch (_: Throwable) {}
            return false
        }

        micMeterRunning = true
        currentMicLevel = 0.0
        val thread = Thread({
            val buffer = ShortArray(1024)
            try {
                record.startRecording()
                while (micMeterRunning) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        var sumSq = 0.0
                        for (i in 0 until read) {
                            val sample = buffer[i] / 32768.0
                            sumSq += sample * sample
                        }
                        val rms = sqrt(sumSq / read)
                        // Gain doux pour une jauge visuelle réactive à la voix normale.
                        val normalized = (rms * 5.5).coerceIn(0.0, 1.0)
                        currentMicLevel = currentMicLevel * 0.35 + normalized * 0.65
                    } else {
                        Thread.sleep(40)
                    }
                }
            } catch (_: Throwable) {
                // Ignoré en cas d'arrêt concurrent.
            } finally {
                currentMicLevel = 0.0
                try {
                    record.stop()
                } catch (_: Throwable) {}
                try {
                    record.release()
                } catch (_: Throwable) {}
            }
        }, "videolog-mic-meter")
        thread.isDaemon = true
        micMeterThread = thread
        thread.start()
        return true
    }

    @Synchronized
    private fun stopMicMeter() {
        micMeterRunning = false
        currentMicLevel = 0.0
        val thread = micMeterThread
        micMeterThread = null
        if (thread != null && thread.isAlive) {
            try {
                thread.join(250)
            } catch (_: InterruptedException) {}
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipEnabled && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }

    // Bip court (120 ms) sur le flux notification : suit le volume des notifications du téléphone.
    private fun playBeep(): Boolean {
        return try {
            val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 70)
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
            Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 500)
            true
        } catch (e: RuntimeException) {
            false
        }
    }

    // Android impose un ratio entre 1:2.39 et 2.39:1.
    private fun safeRatio(w: Int, h: Int): Rational {
        if (w <= 0 || h <= 0) return DEFAULT_RATIO
        val r = w.toFloat() / h
        return when {
            r > 2.39f -> Rational(239, 100)
            r < 1f / 2.39f -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    private fun supportsPip(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun isInPipMode(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode
    }

    private fun updatePipParams() {
        if (!supportsPip()) return
        try {
            setPictureInPictureParams(buildPipParams())
        } catch (e: IllegalStateException) {
            // Activity not in a valid state to receive PiP params.
        } catch (e: IllegalArgumentException) {
            // Invalid params (e.g. aspect ratio out of range).
        }
    }

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(pipAspectRatio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipEnabled)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun enterPip(): Boolean {
        if (!supportsPip()) return false
        return try {
            enterPictureInPictureMode(buildPipParams())
        } catch (e: IllegalStateException) {
            false
        } catch (e: IllegalArgumentException) {
            false
        }
    }
}