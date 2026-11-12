package com.lhht.ai_assistant.robot

import android.content.Context
import android.app.Activity
import android.view.WindowManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Flutter bridge "robot" exposing head and wheel control of the Visbot via [RosaClient].
 *
 * Methods:
 *  - isAvailable -> bool
 *  - locomotionDevice -> {id, name, min/max/defaultTurningSpeed, min/max/defaultMovingSpeed}
 *  - servoDevices -> list of {id, name, minAngle, maxAngle, minSpeed, maxSpeed, defaultSpeed}
 *  - head {angle, speed?, servoId?, relative?} -> {result, code, message} once the move ends
 *  - move {speed?, angle?, distance?, turnSpeed?, turnAngle?, durationMs?} -> {result, code, message}
 *  - stop -> null (cancels the current wheel movement)
 */
class RobotChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val client = RosaClient(context.applicationContext)
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var currentMove: RosaClient.CallHandle? = null
    @Volatile
    private var currentHead: RosaClient.CallHandle? = null
    @Volatile
    private var moveReply: Reply? = null
    @Volatile
    private var headReply: Reply? = null

    private fun cancelMotion() {
        currentMove?.let { client.cancel(it) }
        currentHead?.let { client.cancel(it) }
        currentMove = null
        currentHead = null
        val canceled = mapOf("result" to "canceled", "message" to "Động tác đã bị dừng")
        moveReply?.ok(canceled)
        headReply?.ok(canceled)
        moveReply = null
        headReply = null
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.execute { cancelMotion(); client.disconnect() }
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "keepScreenOn" -> {
                val window = (context as? Activity)?.window
                if (call.argument<Boolean>("enabled") == true) {
                    window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            "isAvailable" -> result.success(isMasterInstalled())
            "servoDevices" -> runAsync(result) { reply ->
                client.servoDevices { devices, response ->
                    if (devices == null) {
                        reply.error(response)
                    } else {
                        reply.ok(devices.map {
                            mapOf(
                                "id" to it.id,
                                "name" to it.name,
                                "minAngle" to it.minAngle.toDouble(),
                                "maxAngle" to it.maxAngle.toDouble(),
                                "minSpeed" to it.minSpeed.toDouble(),
                                "maxSpeed" to it.maxSpeed.toDouble(),
                                "defaultSpeed" to it.defaultSpeed.toDouble(),
                            )
                        })
                    }
                }
            }
            "locomotionDevice" -> runAsync(result) { reply ->
                client.locomotionDevice { device, response ->
                    if (device == null) reply.error(response) else reply.ok(device)
                }
            }
            "head" -> runAsync(result) { reply ->
                currentHead?.let { client.cancel(it) }
                headReply?.ok(mapOf("result" to "canceled"))
                val option = RosaClient.RotationOption(
                    servoId = call.argument<String>("servoId") ?: "head",
                    angle = call.floatArg("angle"),
                    angleAbsolute = call.argument<Boolean>("relative") != true,
                    speed = call.floatArg("speed"),
                )
                headReply = reply
                var handle: RosaClient.CallHandle? = null
                handle = client.rotate(option) { response ->
                    if (response.resultType != RosaClient.RESULT_STICKILY) {
                        if (currentHead == handle) { currentHead = null; headReply = null }
                        reply.response(response)
                    }
                }
                currentHead = handle
            }
            "move" -> runAsync(result) { reply ->
                currentMove?.let { client.cancel(it) }
                moveReply?.ok(mapOf("result" to "canceled"))
                moveReply = reply
                val option = RosaClient.LocomotionOption(
                    movingSpeed = call.floatArg("speed"),
                    movingAngle = call.floatArg("angle"),
                    movingDistance = call.floatArg("distance"),
                    turningSpeed = call.floatArg("turnSpeed"),
                    turningAngle = call.floatArg("turnAngle"),
                    durationMs = (call.argument<Number>("durationMs") ?: 0).toLong(),
                )
                var handle: RosaClient.CallHandle? = null
                handle = client.locomote(option) { response ->
                    if (response.resultType != RosaClient.RESULT_STICKILY) {
                        if (currentMove == handle) { currentMove = null; moveReply = null }
                        reply.response(response)
                    }
                }
                currentMove = handle
            }
            "motionSeries" -> runAsync(result) { reply ->
                val kind = call.argument<String>("kind")
                val poses = call.argument<List<Map<String, Number>>>("poses") ?: emptyList()
                require(poses.size in 1..16) { "Invalid motion series" }
                val durations = poses.map { (it["durationMs"] ?: 0).toLong() }
                require(durations.all { it in 60..1500 } && durations.sum() <= 6000)
                if (kind == "head") {
                    val options = poses.mapIndexed { index, pose ->
                        val angle = pose["angle"]!!.toFloat()
                        require(angle in -23f..25f)
                        RosaClient.RotationOption("head", angle, durationMs = durations[index])
                    }
                    currentHead?.let { client.cancel(it) }
                    headReply?.ok(mapOf("result" to "canceled"))
                    headReply = reply
                    var handle: RosaClient.CallHandle? = null
                    handle = client.rotateSeries(options) { response ->
                        if (response.resultType != RosaClient.RESULT_STICKILY) {
                            if (currentHead == handle) { currentHead = null; headReply = null }
                            reply.response(response)
                        }
                    }
                    currentHead = handle
                } else {
                    require(kind == "wheels")
                    val options = poses.mapIndexed { index, pose ->
                        val speed = pose["speed"]!!.toFloat()
                        require(speed in -2f..2f && speed != 0f)
                        RosaClient.LocomotionOption(movingSpeed = speed, durationMs = durations[index])
                    }
                    currentMove?.let { client.cancel(it) }
                    moveReply?.ok(mapOf("result" to "canceled"))
                    moveReply = reply
                    var handle: RosaClient.CallHandle? = null
                    handle = client.locomoteSeries(options) { response ->
                        if (response.resultType != RosaClient.RESULT_STICKILY) {
                            if (currentMove == handle) { currentMove = null; moveReply = null }
                            reply.response(response)
                        }
                    }
                    currentMove = handle
                }
            }
            "stop" -> runAsync(result) { reply ->
                cancelMotion()
                reply.ok(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun isMasterInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(MASTER_PACKAGE, 0)
        true
    } catch (e: Exception) {
        false
    }

    private fun finalResponse(reply: Reply) = RosaClient.ResponseListener { response ->
        if (response.resultType != RosaClient.RESULT_STICKILY) reply.response(response)
    }

    private fun runAsync(result: MethodChannel.Result, block: (Reply) -> Unit) {
        val reply = Reply(result)
        worker.execute {
            try {
                block(reply)
            } catch (e: Exception) {
                Log.e(TAG, "Robot call failed", e)
                reply.fail(e)
            }
        }
    }

    private fun MethodCall.floatArg(name: String): Float =
        (argument<Number>(name) ?: 0).toFloat()

    /** Delivers exactly one reply to Flutter on the main thread. */
    private inner class Reply(private val result: MethodChannel.Result) {
        private var done = false

        fun ok(value: Any?) = post { result.success(value) }

        fun response(response: RosaClient.Response) = ok(
            mapOf(
                "result" to response.resultType,
                "code" to response.code,
                "subCode" to response.subCode,
                "message" to response.message,
            ),
        )

        fun error(response: RosaClient.Response) = post {
            result.error("ROBOT_${response.code}", response.message, response.subCode)
        }

        fun fail(e: Exception) = post { result.error("ROBOT_ERROR", e.message, null) }

        private fun post(action: () -> Unit) {
            mainHandler.post {
                if (!done) {
                    done = true
                    action()
                }
            }
        }
    }

    companion object {
        private const val TAG = "RobotChannel"
        const val CHANNEL = "com.lhht.ai_assistant/robot"
        private const val MASTER_PACKAGE = "com.ubtrobot.master"
    }
}
