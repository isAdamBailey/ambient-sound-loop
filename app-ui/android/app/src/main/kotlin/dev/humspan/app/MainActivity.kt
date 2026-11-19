package dev.humspan.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var listening = false
    private var noisyRegistered = false
    private var focusRequest: AudioFocusRequest? = null

    private val audioManager by lazy { getSystemService(AUDIO_SERVICE) as AudioManager }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var reportedSpeaker: Boolean? = null

    private val mediaAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    // Headphones or a speaker arriving or leaving. The media route can settle
    // a moment after the device list changes, so look again shortly after.
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = routeMayHaveChanged()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = routeMayHaveChanged()
    }
    private val recheckRoute = Runnable { reportRoute() }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                channel?.invokeMethod("outputLost", null)
            }
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        val method = when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> "focusLoss"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "focusTransient"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "focusDuck"
            AudioManager.AUDIOFOCUS_GAIN -> "focusGain"
            else -> return@OnAudioFocusChangeListener
        }
        channel?.invokeMethod(method, null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, "dev.humspan/session")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "outputRoute" -> {
                    val speaker = isSpeakerRoute()
                    reportedSpeaker = speaker
                    result.success(speaker)
                }
                "setListening" -> {
                    if (call.arguments == true) startListening() else stopListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
    }

    override fun onDestroy() {
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        mainHandler.removeCallbacks(recheckRoute)
        stopListening()
        channel?.setMethodCallHandler(null)
        super.onDestroy()
    }

    private fun routeMayHaveChanged() {
        reportRoute()
        mainHandler.removeCallbacks(recheckRoute)
        mainHandler.postDelayed(recheckRoute, 750)
    }

    private fun reportRoute() {
        val speaker = isSpeakerRoute()
        if (speaker == reportedSpeaker) return
        reportedSpeaker = speaker
        channel?.invokeMethod("outputRoute", speaker)
    }

    /** True when media plays from the device's own speaker. */
    private fun isSpeakerRoute(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val route = audioManager.getAudioDevicesForAttributes(mediaAttributes)
            if (route.isNotEmpty()) {
                return route.all { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            }
        }
        // Older systems: the speaker plays media unless something else is attached.
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).none { it.type in externalOutputs }
    }

    private val externalOutputs = setOf(
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_LINE_DIGITAL,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_DOCK,
        AudioDeviceInfo.TYPE_HEARING_AID,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
    )

    private fun startListening() {
        if (listening) return
        listening = true
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(noisyReceiver, filter)
        }
        noisyRegistered = true
        requestFocus()
    }

    private fun stopListening() {
        if (noisyRegistered) {
            unregisterReceiver(noisyReceiver)
            noisyRegistered = false
        }
        abandonFocus()
        listening = false
    }

    private fun requestFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(mediaAttributes)
                .setOnAudioFocusChangeListener(focusListener)
                .setWillPauseWhenDucked(false)
                .build()
                .also { focusRequest = it }
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }
}
