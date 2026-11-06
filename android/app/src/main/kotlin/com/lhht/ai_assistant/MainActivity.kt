package com.lhht.ai_assistant

import com.lhht.ai_assistant.robot.RobotChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var robotChannel: RobotChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        robotChannel = RobotChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        robotChannel?.dispose()
        robotChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
