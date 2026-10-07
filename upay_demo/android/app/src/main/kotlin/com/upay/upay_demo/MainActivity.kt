package com.upay.upay_demo

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "upay/audio")
            .setMethodCallHandler { call, result ->
                if (call.method != "speaker") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                // Speech recognition leaves some phones in call mode. The next
                // voice then plays into the earpiece, so the user only sees text.
                try {
                    @Suppress("DEPRECATION")
                    audio.stopBluetoothSco()
                    @Suppress("DEPRECATION")
                    audio.isBluetoothScoOn = false
                } catch (ignored: Exception) {
                }
                audio.mode = AudioManager.MODE_NORMAL
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audio.clearCommunicationDevice()
                }
                @Suppress("DEPRECATION")
                audio.isSpeakerphoneOn = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                .build(),
                        )
                        .build()
                    audio.requestAudioFocus(request)
                } else {
                    @Suppress("DEPRECATION")
                    audio.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
                }
                result.success(null)
            }
    }
}
