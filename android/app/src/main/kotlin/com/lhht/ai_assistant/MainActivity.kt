package com.lhht.ai_assistant

import android.content.Intent
import com.lhht.ai_assistant.standby.ScreenPowerChannel
import com.lhht.ai_assistant.audio.PcmStreamPlayer
import com.lhht.ai_assistant.robot.RobotChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var robotChannel: RobotChannel? = null
    private var screenPower: ScreenPowerChannel? = null
    private var pcmPlayer: PcmStreamPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        robotChannel = RobotChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        screenPower = ScreenPowerChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        pcmPlayer = PcmStreamPlayer(flutterEngine.dartExecutor.binaryMessenger)
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
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
