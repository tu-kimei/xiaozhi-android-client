package com.lhht.ai_assistant.robot

import android.content.Context
import android.net.Uri
import android.os.Binder
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Minimal client for the UBTech ROSA "Master" broker running on Visbot robots.
 *
 * Speaks the broker's binder protocol directly: one client binder is handed to the
 * master via the `com.ubtrobot.provider.master` ContentProvider, then requests and
 * responses travel as hand-marshalled parcels. UBTech class names appear only as the
 * string tags the master expects on the wire.
 */
class RosaClient(private val context: Context) {

    data class Response(
        val requestId: String,
        val resultType: String,
        val code: Int,
        val message: String?,
        val subCode: Int,
        val paramType: String?,
        val paramBytes: ByteArray?,
    )

    fun interface ResponseListener {
        fun onResponse(response: Response)
    }

    data class ServoDevice(
        val id: String,
        val name: String?,
        val minAngle: Float,
        val maxAngle: Float,
        val minSpeed: Float,
        val maxSpeed: Float,
        val defaultSpeed: Float,
    )

    data class RotationOption(
        val servoId: String,
        val angle: Float,
        val angleAbsolute: Boolean = true,
        val durationMs: Long = 0,
        val speed: Float = 0f,
    )

    data class LocomotionOption(
        val movingSpeed: Float = 0f,
        val movingAngle: Float = 0f,
        val movingDistance: Float = 0f,
        val turningSpeed: Float = 0f,
        val turningAngle: Float = 0f,
        val turningAxis: Int = 0,
        val durationMs: Long = 0,
        val emergency: Boolean = false,
    )

    /** A resource the call competes for; optional items don't block the call when busy. */
    data class CompetingItem(val service: String, val itemId: String, val optional: Boolean = false)

    data class Session(val id: String, val items: List<CompetingItem>)

    /** Identifies an in-flight sticky call so it can be cancelled later. */
    data class CallHandle(
        val requestId: String,
        val service: String,
        val path: String,
        val session: Session?,
    )

    private val listeners = ConcurrentHashMap<String, ResponseListener>()
    private val idCounter = AtomicLong()
    private val idPrefix = UUID.randomUUID().toString().substring(0, 5)
    private val sessionIds = ConcurrentHashMap<String, String>()

    @Volatile
    private var masterBinder: IBinder? = null

    private val clientBinder = object : Binder() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            return when (code) {
                TRANS_CODE_WRITE -> {
                    try {
                        handleIncoming(data)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to decode message from master", e)
                    }
                    true
                }
                TRANS_CODE_DISCONNECT -> {
                    Log.w(TAG, "Master closed the connection")
                    masterBinder = null
                    true
                }
                else -> super.onTransact(code, data, reply, flags)
            }
        }
    }

    val isConnected: Boolean
        get() = masterBinder?.isBinderAlive == true

    @Synchronized
    fun connect() {
        if (isConnected) return

        val extras = Bundle().apply {
            putString("version", "v1")
            putString("package", context.packageName)
            putBinder("binder", clientBinder)
        }
        val result = context.contentResolver.call(
            Uri.parse("content://$MASTER_AUTHORITY"), "connect", null, extras,
        ) ?: throw IllegalStateException("Master returned no result")

        val code = result.getInt("code", -1)
        if (code != 0) {
            throw IllegalStateException(
                "Master refused connection: code=$code, ${result.getString("error_message")}",
            )
        }
        masterBinder = result.getBinder("binder")
            ?: throw IllegalStateException("Master returned no binder")
        Log.i(TAG, "Connected to ROSA master")
    }

    fun disconnect() {
        val binder = masterBinder ?: return
        val data = Parcel.obtain()
        try {
            data.writeStrongBinder(clientBinder)
            binder.transact(TRANS_CODE_DISCONNECT, data, null, 0)
        } catch (e: Exception) {
            Log.w(TAG, "Disconnect failed", e)
        } finally {
            data.recycle()
            masterBinder = null
            listeners.clear()
        }
    }

    // ---- High level API ----

    fun servoDevices(listener: (List<ServoDevice>?, Response) -> Unit) {
        call("servo", "/servo/device/list", sticky = false) { response ->
            val devices = if (response.resultType == RESULT_SUCCESS) {
                response.paramBytes?.let { decodeServoDeviceList(it) }
            } else {
                null
            }
            listener(devices, response)
        }
    }

    /** Raw `/locomotor/device` result: id, name, then turning and moving speed ranges. */
    fun locomotionDevice(listener: (Map<String, Any?>?, Response) -> Unit) {
        call("locomotion", "/locomotor/device", sticky = false) { response ->
            val bytes = response.paramBytes
            val device = if (response.resultType == RESULT_SUCCESS && bytes != null) {
                val p = Parcel.obtain()
                try {
                    p.unmarshall(bytes, 0, bytes.size)
                    p.setDataPosition(0)
                    p.readString() // LocomotionDevice class name
                    mapOf(
                        "id" to p.readString(),
                        "name" to p.readString(),
                        "description" to p.readString(),
                        "minTurningSpeed" to p.readFloat().toDouble(),
                        "maxTurningSpeed" to p.readFloat().toDouble(),
                        "defaultTurningSpeed" to p.readFloat().toDouble(),
                        "minMovingSpeed" to p.readFloat().toDouble(),
                        "maxMovingSpeed" to p.readFloat().toDouble(),
                        "defaultMovingSpeed" to p.readFloat().toDouble(),
                    )
                } finally {
                    p.recycle()
                }
            } else {
                null
            }
            listener(device, response)
        }
    }

    fun rotate(option: RotationOption, listener: ResponseListener?): CallHandle {
        val session = competitionSession(listOf(CompetingItem("servo", "servo-${option.servoId}")))
        return call(
            service = "servo",
            path = "/servo/rotate",
            sticky = true,
            param = parcelableParam(ROTATION_OPTION_LIST) { p ->
                p.writeInt(1)
                p.writeInt(1)
                p.writeString(option.servoId)
                p.writeFloat(option.angle)
                p.writeByte(if (option.angleAbsolute) 1 else 0)
                p.writeLong(option.durationMs)
                p.writeFloat(option.speed)
            },
            session = session,
            listener = listener,
        )
    }

    fun locomote(option: LocomotionOption, listener: ResponseListener?): CallHandle {
        return call(
            service = "locomotion",
            path = "/locomotor/locomote",
            sticky = true,
            param = parcelableParam(LOCOMOTION_OPTION_LIST) { p ->
                p.writeInt(1)
                p.writeInt(1)
                p.writeFloat(option.movingSpeed)
                p.writeFloat(option.movingAngle)
                p.writeFloat(option.movingDistance)
                p.writeFloat(option.turningSpeed)
                p.writeFloat(option.turningAngle)
                p.writeInt(option.turningAxis)
                p.writeLong(option.durationMs)
                p.writeByte(if (option.emergency) 1 else 0)
            },
            session = competitionSession(LOCOMOTION_COMPETING_ITEMS),
            listener = listener,
        )
    }

    /** Cancels a sticky call (stops a rotation or the wheels). */
    fun cancel(handle: CallHandle) {
        listeners.remove(handle.requestId)
        send(
            requestId = nextId(),
            service = handle.service,
            path = handle.path,
            hasCallback = false,
            sticky = false,
            cancelPrevious = true,
            previousRequestId = handle.requestId,
            param = EMPTY_PARAM,
            session = handle.session,
        )
    }

    // ---- Request plumbing ----

    private fun call(
        service: String,
        path: String,
        sticky: Boolean,
        param: Pair<String, ByteArray> = EMPTY_PARAM,
        session: Session? = null,
        listener: ResponseListener? = null,
    ): CallHandle {
        val requestId = nextId()
        if (listener != null) listeners[requestId] = listener
        send(requestId, service, path, true, sticky, false, null, param, session)
        return CallHandle(requestId, service, path, session)
    }

    private fun send(
        requestId: String,
        service: String,
        path: String,
        hasCallback: Boolean,
        sticky: Boolean,
        cancelPrevious: Boolean,
        previousRequestId: String?,
        param: Pair<String, ByteArray>,
        session: Session?,
    ) {
        connect()
        val binder = masterBinder ?: throw IllegalStateException("Not connected to master")

        val data = Parcel.obtain()
        try {
            data.writeStrongBinder(clientBinder)

            // ParcelMessage { serializable(content class), parcelable(content) }
            data.writeString(PARCEL_MESSAGE)
            writeSerializableClass(data, PARCEL_REQUEST)

            // ParcelRequest
            data.writeString(PARCEL_REQUEST)
            data.writeString(requestId)
            data.writeLong(System.currentTimeMillis())

            data.writeString(PARCEL_REQUEST_CONTEXT)
            data.writeString("global-context")
            data.writeString(null)
            data.writeString("service")
            data.writeString(service)
            data.writeString(null)
            if (session == null) {
                data.writeByte(0)
            } else {
                data.writeByte(1)
                writeSerializableClass(data, COMPETITION_SESSION_INFO)
                data.writeString(COMPETITION_SESSION_INFO)
                data.writeString(session.id)
                data.writeInt(session.items.size)
                for (item in session.items) {
                    data.writeInt(1)
                    data.writeString(item.service)
                    data.writeString(item.itemId)
                    data.writeByte(if (item.optional) 1 else 0)
                }
            }

            data.writeString(PARCEL_REQUEST_CONFIG)
            data.writeByte(if (hasCallback) 1 else 0)
            data.writeByte(if (sticky) 1 else 0)
            data.writeInt(DEFAULT_TIMEOUT_MS)
            data.writeByte(if (cancelPrevious) 1 else 0)
            data.writeString(previousRequestId)

            data.writeString("")

            data.writeString(PARCEL_PARAM_WRAP)
            data.writeString(param.first)
            data.writeByteArray(param.second)

            data.writeString(path)

            binder.transact(TRANS_CODE_WRITE, data, null, 0)
            Log.d(TAG, "Sent $path ($requestId) to $service")
        } finally {
            data.recycle()
        }
    }

    private fun handleIncoming(data: Parcel) {
        data.readString() // ParcelMessage class name
        data.readString() // serializable type ("java.lang.Class")
        data.createByteArray() // serialized content class
        val contentClass = data.readString()
        if (contentClass != PARCEL_RESPONSE) {
            Log.d(TAG, "Ignoring message of type $contentClass")
            return
        }

        data.readString() // response id
        data.readLong() // when
        val requestId = data.readString() ?: return
        data.readString() // request connection id
        data.readString() // path
        val resultType = data.readString() ?: ""
        val code = data.readInt()
        val message = data.readString()
        val subCode = data.readInt()
        data.readString() // ParcelParamWrap class name
        val paramType = data.readString()
        val paramBytes = data.createByteArray()

        val response = Response(requestId, resultType, code, message, subCode, paramType, paramBytes)
        Log.d(TAG, "Response $requestId: $resultType code=$code msg=$message")

        val listener = if (resultType == RESULT_STICKILY) {
            listeners[requestId]
        } else {
            listeners.remove(requestId)
        }
        listener?.onResponse(response)
    }

    private fun nextId() = "$idPrefix-${idCounter.incrementAndGet()}"

    /** One session per set of competing items, reused across calls like the SDK does. */
    private fun competitionSession(items: List<CompetingItem>): Session {
        val sorted = items.sortedBy { it.itemId }
        val key = sorted.joinToString("") { "${it.service}/${it.itemId}" }
        val sessionId = sessionIds.getOrPut(key) { "${System.nanoTime()}-" }
        return Session(sessionId, sorted)
    }

    private fun decodeServoDeviceList(bytes: ByteArray): List<ServoDevice> {
        val p = Parcel.obtain()
        try {
            p.unmarshall(bytes, 0, bytes.size)
            p.setDataPosition(0)
            p.readString() // ServoDeviceList class name
            val count = p.readInt()
            val devices = ArrayList<ServoDevice>(maxOf(count, 0))
            repeat(count) {
                if (p.readInt() == 0) return@repeat
                val id = p.readString() ?: ""
                val name = p.readString()
                p.readString() // description
                devices.add(
                    ServoDevice(
                        id = id,
                        name = name,
                        minAngle = p.readFloat(),
                        maxAngle = p.readFloat(),
                        minSpeed = p.readFloat(),
                        maxSpeed = p.readFloat(),
                        defaultSpeed = p.readFloat(),
                    ),
                )
            }
            return devices
        } finally {
            p.recycle()
        }
    }

    companion object {
        private const val TAG = "RosaClient"

        private const val MASTER_AUTHORITY = "com.ubtrobot.provider.master"
        private const val TRANS_CODE_WRITE = 1465010516
        private const val TRANS_CODE_DISCONNECT = 1146307406
        private const val DEFAULT_TIMEOUT_MS = 15000

        const val RESULT_SUCCESS = "success"
        const val RESULT_FAILURE = "failure"
        const val RESULT_STICKILY = "stickily"

        private const val PKG = "com.ubtrobot.master.transport.message.parcel"
        private const val PARCEL_MESSAGE = "$PKG.ParcelMessage"
        private const val PARCEL_REQUEST = "$PKG.ParcelRequest"
        private const val PARCEL_REQUEST_CONTEXT = "$PKG.ParcelRequestContext"
        private const val PARCEL_REQUEST_CONFIG = "$PKG.ParcelRequestConfig"
        private const val PARCEL_PARAM_WRAP = "$PKG.ParcelParamWrap"
        private const val PARCEL_RESPONSE = "$PKG.ParcelResponse"
        private const val COMPETITION_SESSION_INFO = "com.ubtrobot.competition.CompetitionSessionInfo"
        private const val ROTATION_OPTION_LIST = "com.ubtrobot.servo.RotationOptionList"
        private const val LOCOMOTION_OPTION_LIST = "com.ubtrobot.locomotion.LocomotionOptionList"

        private val EMPTY_PARAM = "EmptyParam" to ByteArray(0)

        private val LOCOMOTION_COMPETING_ITEMS = listOf(
            CompetingItem("navigation", "navigator", optional = true),
            CompetingItem("recharging", "charging-station-connection", optional = true),
        )

        /** A ParcelableParam: the parcelable (class tag + body) marshalled into bytes. */
        private fun parcelableParam(className: String, body: (Parcel) -> Unit): Pair<String, ByteArray> {
            val p = Parcel.obtain()
            try {
                p.writeString(className)
                body(p)
                return "ParcelableParam" to p.marshall()
            } finally {
                p.recycle()
            }
        }

        /**
         * Equivalent of Parcel.writeSerializable(SomeClass::class.java) for a class this
         * process doesn't have: a java.lang.Class object serialized by ObjectOutputStream.
         * The master's classes are not Serializable, so the descriptor has suid 0 and no flags.
         */
        private fun writeSerializableClass(parcel: Parcel, className: String) {
            val bytes = ByteArrayOutputStream()
            DataOutputStream(bytes).use { out ->
                out.writeShort(0xACED) // STREAM_MAGIC
                out.writeShort(5) // STREAM_VERSION
                out.writeByte(0x76) // TC_CLASS
                out.writeByte(0x72) // TC_CLASSDESC
                out.writeUTF(className)
                out.writeLong(0L) // serialVersionUID
                out.writeByte(0) // flags
                out.writeShort(0) // field count
                out.writeByte(0x78) // TC_ENDBLOCKDATA
                out.writeByte(0x70) // TC_NULL (no serializable superclass)
            }
            parcel.writeString("java.lang.Class")
            parcel.writeByteArray(bytes.toByteArray())
        }
    }
}
