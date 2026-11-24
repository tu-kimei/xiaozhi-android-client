package com.lhht.ai_assistant.vision

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Metadata-only Flutter boundary. No JPEG bytes, filesystem path or upload endpoint. */
class VisionChannel(activity: Activity, messenger: BinaryMessenger) {
    private val methods = MethodChannel(messenger, "visbot/vision")
    private val events = EventChannel(messenger, "visbot/vision/events")
    private var sink: EventChannel.EventSink? = null
    private val service = SnapshotCameraService(activity, VisionReferenceStore(activity), createParentPinGate(activity)) { sink?.success(it) }

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        methods.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            fun respond(value: Map<String, Any>?, code: String?) {
                if (code == null) result.success(value)
                else {
                    val safe = when (code) {
                        "busy" -> "camera_busy"
                        "timeout" -> "camera_timeout"
                        "invalid_argument" -> "invalid_request"
                        "capture_failed", "invalid_image" -> "camera_capture"
                        "storage_unavailable" -> "storage_error"
                        "not_ready", "closed", "unavailable", "camera_unavailable" -> "camera_unavailable"
                        "permission_denied", "consent_required", "not_foreground", "cancelled" -> code
                        "parent_auth_required", "pin_required", "pin_not_configured",
                        "pin_invalid", "pin_locked", "invalid_pin", "pin_storage" -> code
                        else -> "camera_unavailable"
                    }
                    result.error(safe, safe, null)
                }
            }
            when (call.method) {
                "getCapabilities" -> result.success(service.capabilities())
                "getParentGateStatus" -> {
                    try { result.success(service.gateStatus()) }
                    catch (_: Exception) { respond(null, "pin_storage") }
                }
                "configureParentPin" -> {
                    val newPin = args?.get("newPin") as? String
                    val currentPin = args?.get("currentPin") as? String
                    if (newPin == null || (args?.containsKey("currentPin") == true && currentPin == null)) {
                        respond(null, "invalid_argument")
                    } else service.configurePin(newPin, currentPin, ::respond)
                }
                "authorizeParentPin" -> {
                    val pin = args?.get("pin") as? String
                    if (pin == null) respond(null, "invalid_argument")
                    else service.authorizePin(pin, ::respond)
                }
                "setConsent" -> {
                    val enabled = args?.get("enabled") as? Boolean
                    if (enabled == null) respond(null, "invalid_argument")
                    else service.setConsent(enabled) { code -> respond(emptyMap(), code) }
                }
                "startPrewarm" -> service.start(::respond)
                "captureSnapshot" -> {
                    val id = args?.get("requestId") as? String
                    if (id == null) respond(null, "invalid_argument")
                    else service.capture(id, ::respond)
                }
                "cancel" -> {
                    val id = args?.get("requestId") as? String
                    if (id == null) respond(null, "invalid_argument")
                    else service.cancel(id) { code -> respond(emptyMap(), code) }
                }
                "deleteSnapshot" -> {
                    val reference = args?.get("reference") as? String
                    if (reference == null) respond(null, "invalid_argument")
                    else service.delete(reference, ::respond)
                }
                "cleanupStaleSnapshots" -> service.cleanup(::respond)
                "close" -> service.revoke { code -> respond(emptyMap(), code) }
                else -> result.notImplemented()
            }
        }
    }

    fun onResume() = service.setForeground(true)
    fun onPause() = service.setForeground(false)
    fun onScreenOff() = service.revoke()
    fun dispose() {
        service.dispose()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
    }
}
