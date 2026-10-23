package com.opkodelabs.videolog_coach

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "videolog/pip"
    }

    private var pipChannel: MethodChannel? = null
    private var pipEnabled = false
    private var pipAspectRatio = Rational(9, 16)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(supportsPip())
                "enableAutoEnter" -> {
                    val width = call.argument<Int>("width") ?: 9
                    val height = call.argument<Int>("height") ?: 16
                    pipAspectRatio = Rational(width, height)
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
                    pipEnabled = true
                    updatePipParams()
                    result.success(enterPip())
                }
                "isInPip" -> result.success(isInPipMode())
                else -> result.notImplemented()
            }
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
            // Activity is not in a valid state to receive PiP params.
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
        }
    }
}
