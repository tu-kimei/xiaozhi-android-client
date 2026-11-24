package com.lhht.ai_assistant

import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.content.Context
import com.lhht.ai_assistant.standby.ScreenPowerChannel
import com.lhht.ai_assistant.audio.PcmStreamPlayer
import com.lhht.ai_assistant.robot.RobotChannel
import com.lhht.ai_assistant.vision.VisionChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var robotChannel: RobotChannel? = null
    private var screenPower: ScreenPowerChannel? = null
    private var pcmPlayer: PcmStreamPlayer? = null
    private var visionChannel: VisionChannel? = null
    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) visionChannel?.onScreenOff()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        robotChannel = RobotChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        screenPower = ScreenPowerChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        pcmPlayer = PcmStreamPlayer(flutterEngine.dartExecutor.binaryMessenger)
        visionChannel = VisionChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        registerReceiver(screenOffReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
        visionChannel?.onResume()
    }

    override fun onPause() {
        visionChannel?.onPause()
        unregisterReceiver(screenOffReceiver)
        super.onPause()
    }

    override fun onStop() {
        visionChannel?.onPause()
        super.onStop()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (screenPower?.onActivityResult(requestCode) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        screenPower?.dispose()
        screenPower = null
        robotChannel?.dispose()
        robotChannel = null
        pcmPlayer?.dispose()
        pcmPlayer = null
        visionChannel?.dispose()
        visionChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

}
