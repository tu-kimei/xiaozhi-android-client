package com.lhht.ai_assistant.vision

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.Camera
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import java.util.concurrent.atomic.AtomicLong

/**
 * Camera API1 is owned exclusively by [worker]. Callbacks never wait for one another.
 * Revocation advances [generation] synchronously, before queued release can run.
 */
internal class SnapshotCameraService(
    private val activity: Activity,
    private val store: VisionReferenceStore,
    private val parentGate: ParentPinGate,
    private val emit: (Map<String, Any>) -> Unit,
) {
    private val thread = HandlerThread("vision-camera").also { it.start() }
    private val worker = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicLong()
    private val fence = VisionLifecycleFence(SystemClock::elapsedRealtime, generation)
    @Volatile private var consent = false
    @Volatile private var consentUntil = 0L
    @Volatile private var foreground = false
    @Volatile private var disposed = false
    private var camera: Camera? = null // worker only
    @Volatile private var state = "closed" // writes on worker, read at event delivery
    private var openingAt = 0L
    private var idleAt = 0L
    private var frames = 0
    private var warmedCapture = false
    private var pending: Pending? = null

    private data class Pending(
        val id: String,
        val token: Long,
        val deadline: Long,
        val respond: (Map<String, Any>?, String?) -> Unit,
        val ticket: VisionLifecycleFence.Ticket,
    )

    fun capabilities(): Map<String, Any> {
        val available = try {
            (0 until Camera.getNumberOfCameras()).any {
                val info = Camera.CameraInfo()
                Camera.getCameraInfo(it, info)
                it == 0 && info.facing == Camera.CameraInfo.CAMERA_FACING_BACK
            }
        } catch (_: Exception) { false }
        return mapOf("backend" to "api1", "available" to available)
    }

    fun setForeground(value: Boolean) {
        foreground = value
        // revoke() invalidates generation/consent before any gate bookkeeping,
        // so backgrounding cannot wait behind a slow PIN derivation.
        if (!value) revoke()
    }

    fun setConsent(value: Boolean, complete: ((String?) -> Unit)? = null) {
        if (value) {
            if (!foreground || !(activity.getSystemService(Activity.POWER_SERVICE) as PowerManager).isInteractive) {
                complete?.invoke("not_foreground"); return
            }
            if (!parentGate.consume()) { complete?.invoke("parent_auth_required"); return }
            consent = true
            consentUntil = SystemClock.elapsedRealtime() + 60_000L
            val deadline = consentUntil
            main.postDelayed({
                if (consent && consentUntil == deadline) setConsent(false)
            }, 60_000L)
            complete?.invoke(null)
        } else {
            revoke(complete)
        }
    }

    fun gateStatus(): Map<String, Any> = mapOf("pinConfigured" to parentGate.configured(), "authorized" to parentGate.authorized())

    fun configurePin(newPin: String, currentPin: String?, respond: (Map<String, Any>?, String?) -> Unit) {
        if (!foreground || !(activity.getSystemService(Activity.POWER_SERVICE) as PowerManager).isInteractive) {
            respond(null, "not_foreground"); return
        }
        val token = generation.get()
        worker.post {
            try {
                if (!foreground || generation.get() != token) throw VisionFailure("not_foreground")
                parentGate.enroll(newPin, currentPin)
                if (!foreground || generation.get() != token) throw VisionFailure("not_foreground")
                reply(respond, emptyMap(), null)
            }
            catch (failure: VisionFailure) { reply(respond, null, failure.code) }
        }
    }

    fun authorizePin(pin: String, respond: (Map<String, Any>?, String?) -> Unit) {
        if (!foreground || !(activity.getSystemService(Activity.POWER_SERVICE) as PowerManager).isInteractive) {
            respond(null, "not_foreground"); return
        }
        val token = generation.get()
        worker.post {
            try {
                if (!foreground || generation.get() != token) throw VisionFailure("not_foreground")
                parentGate.authorize(pin)
                if (!foreground || generation.get() != token) {
                    parentGate.revoke()
                    throw VisionFailure("not_foreground")
                }
                reply(respond, emptyMap(), null)
            } catch (failure: VisionFailure) { reply(respond, null, failure.code) }
        }
    }

    fun guard(): String? = when {
        disposed -> "closed"
        !consent || SystemClock.elapsedRealtime() >= consentUntil -> "consent_required"
        !foreground || !(activity.getSystemService(Activity.POWER_SERVICE) as PowerManager).isInteractive -> "not_foreground"
        activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED -> "permission_denied"
        else -> null
    }

    fun start(respond: (Map<String, Any>?, String?) -> Unit) {
        guard()?.let { respond(null, it); return }
        val requestedGeneration = generation.get()
        worker.post {
            if (guard() != null) {
                reply(respond, null, guard() ?: "cancelled"); return@post
            }
            // Two starts queued before Camera.open share its session; a request
            // from before a close must not attach to a later, unrelated session.
            if (camera != null && (generation.get() == requestedGeneration ||
                    generation.get() == requestedGeneration + 1)) {
                val token = generation.get()
                reply(respond, status(), null, fence.Ticket(token, openingAt + 60_000L))
                return@post
            }
            if (generation.get() != requestedGeneration) {
                reply(respond, null, "cancelled"); return@post
            }
            val token = generation.incrementAndGet()
            openingAt = SystemClock.elapsedRealtime()
            idleAt = openingAt
            warmedCapture = false
            frames = 0
            setState("opening")
            scheduleLimits(token)
            main.postDelayed({
                if (generation.compareAndSet(token, token + 1)) worker.post { closeForExpiry() }
            }, 60_000L)
            try {
                val info = Camera.CameraInfo()
                Camera.getCameraInfo(0, info)
                if (info.facing != Camera.CameraInfo.CAMERA_FACING_BACK) throw VisionFailure("unavailable")
                val opened = Camera.open(0)
                camera = opened
                if (generation.get() != token || guard() != null) { release("closed"); reply(respond, null, "cancelled"); return@post }
                val params = opened.parameters
                if (params.supportedPictureSizes.none { it.width == 640 && it.height == 480 }) throw VisionFailure("unavailable")
                val preview = params.supportedPreviewSizes.firstOrNull { it.width == 640 && it.height == 480 }
                    ?: params.supportedPreviewSizes.minByOrNull { it.width.toLong() * it.height }
                    ?: throw VisionFailure("unavailable")
                params.setPictureSize(640, 480)
                params.setPreviewSize(preview.width, preview.height)
                params.previewFormat = ImageFormat.NV21
                params.jpegQuality = 85
                params.setRotation(0)
                opened.parameters = params
                if (!fence.valid(token, openingAt + 60_000L) || guard() != null) {
                    release("closed"); reply(respond, null, "cancelled"); return@post
                }
                startPreview(opened, preview.width, preview.height, token)
                if (!fence.valid(token, openingAt + 60_000L) || guard() != null) {
                    release("closed"); reply(respond, null, "cancelled"); return@post
                }
                reply(respond, status(), null, fence.Ticket(token, openingAt + 60_000L))
            } catch (failure: Exception) {
                val stale = generation.get() != token || guard() != null
                release(if (stale) "closed" else "error")
                reply(respond, null, if (stale) "cancelled" else if (failure is VisionFailure) failure.code else "camera_unavailable")
            }
        }
    }

    private fun startPreview(opened: Camera, width: Int, height: Int, token: Long) {
        frames = 0
        setState("warming")
        val bufferSize = width * height * 3 / 2
        opened.setPreviewCallbackWithBuffer { data, active ->
            // On API1 this callback is dispatched on the Looper of Camera.open (worker).
            if (generation.get() != token || camera !== active) return@setPreviewCallbackWithBuffer
            if (data != null) {
                frames++
                active.addCallbackBuffer(data)
                if (frames == 1) {
                    setState("ready")
                    captureIfReady()
                }
            }
        }
        repeat(3) { opened.addCallbackBuffer(ByteArray(bufferSize)) }
        opened.startPreview()
    }

    fun capture(id: String, respond: (Map<String, Any>?, String?) -> Unit) {
        guard()?.let { respond(null, it); return }
        if (id.length !in 1..128) { respond(null, "invalid_argument"); return }
        val invokedGeneration = generation.get()
        worker.post {
            if (generation.get() != invokedGeneration) { reply(respond, null, "cancelled"); return@post }
            if (guard() != null) { reply(respond, null, guard() ?: "closed"); return@post }
            if (pending != null || state == "capturing") { reply(respond, null, "busy"); return@post }
            if (camera == null) { reply(respond, null, "not_ready"); return@post }
            val token = generation.get()
            val budget = if (warmedCapture) 3_000L else 12_000L
            val deadline = SystemClock.elapsedRealtime() + budget
            val request = Pending(id, token, deadline, respond, fence.Ticket(token, deadline))
            pending = request
            main.postDelayed({
                if (!request.ticket.isFinished() && generation.compareAndSet(token, token + 1)) {
                    request.ticket.deliver(false, "timeout") { code -> respond(null, code) }
                    worker.post {
                        if (pending === request) pending = null
                        release("closed")
                        try { store.deleteAll() } catch (_: Exception) { setState("error") }
                    }
                }
            }, budget)
            captureIfReady()
        }
    }

    private fun captureIfReady() {
        val request = pending ?: return
        val active = camera ?: return
        if (state != "ready" || frames == 0) return
        if (SystemClock.elapsedRealtime() >= request.deadline || generation.get() != request.token) return
        idleAt = SystemClock.elapsedRealtime()
        setState("capturing")
        try {
            active.takePicture(null, null) { data, source ->
                if (pending !== request || generation.get() != request.token || camera !== source || guard() != null) return@takePicture
                try {
                    val metadata = store.put(data ?: throw VisionFailure("invalid_image"))
                    pending = null
                    if (fence.valid(request.token, request.deadline) && guard() == null && !request.ticket.isFinished()) {
                        reply(request.respond, metadata, null, request.ticket)
                    } else {
                        discardReference(metadata)
                        reply(request.respond, null, "cancelled", request.ticket)
                        release("closed")
                        return@takePicture
                    }
                    warmedCapture = true
                    idleAt = SystemClock.elapsedRealtime()
                    worker.postDelayed({
                        try { store.cleanupStale() } catch (_: Exception) { setState("error") }
                    }, VisionReferenceStore.TTL_MS + 1)
                    val preview = source.parameters.previewSize
                    startPreview(source, preview.width, preview.height, request.token)
                } catch (failure: Exception) {
                    pending = null
                    reply(request.respond, null, if (failure is VisionFailure) failure.code else "capture_failed", request.ticket)
                    revoke()
                }
            }
        } catch (_: Exception) {
            pending = null
            reply(request.respond, null, "capture_failed", request.ticket)
            revoke()
        }
    }

    private fun scheduleLimits(token: Long) {
        worker.postDelayed({
            if (generation.compareAndSet(token, token + 1)) closeForExpiry()
        }, 60_000L)
        fun checkIdle() {
            if (generation.get() != token || camera == null) return
            if (SystemClock.elapsedRealtime() - idleAt >= 30_000L) {
                if (generation.compareAndSet(token, token + 1)) closeForExpiry()
            }
            else worker.postDelayed(::checkIdle, 1_000L)
        }
        worker.postDelayed(::checkIdle, 1_000L)
    }

    fun cancel(id: String, complete: ((String?) -> Unit)? = null) {
        // Fail-closed session-wide cancel, not a selective request cancel: even a
        // stale requestId revokes the camera and all retained references. The ID
        // is for caller correlation only; never allow it to keep capture alive.
        revoke(complete)
    }

    fun revoke(complete: ((String?) -> Unit)? = null) {
        consent = false
        consentUntil = 0L
        generation.incrementAndGet()
        parentGate.revoke()
        worker.post {
            pending?.let { reply(it.respond, null, "cancelled", it.ticket) }
            pending = null
            release("closed")
            val error = try { store.deleteAll(); null } catch (_: Exception) { setState("error"); "storage_unavailable" }
            main.post { complete?.invoke(error) }
        }
    }

    fun delete(reference: String, respond: (Map<String, Any>?, String?) -> Unit) {
        worker.post {
            try { store.delete(reference); reply(respond, emptyMap(), null) }
            catch (failure: VisionFailure) { reply(respond, null, failure.code) }
        }
    }

    fun cleanup(respond: (Map<String, Any>?, String?) -> Unit) {
        worker.post {
            try { store.cleanupStale(); reply(respond, emptyMap(), null) }
            catch (_: Exception) { reply(respond, null, "storage_unavailable") }
        }
    }

    fun dispose() {
        disposed = true
        revoke()
        worker.post { thread.quitSafely() }
    }

    private fun closeForExpiry() {
        consent = false
        consentUntil = 0L
        parentGate.revoke()
        pending?.let { reply(it.respond, null, "timeout", it.ticket) }
        pending = null
        release("closed")
        // A successful capture remains available until its TTL, unless explicitly
        // revoked by the caller or lifecycle. No resolver is exposed at this stage.
    }

    private fun release(next: String) {
        val old = camera
        camera = null
        if (old != null) {
            try { old.setPreviewCallbackWithBuffer(null) } catch (_: Exception) {}
            try { old.stopPreview() } catch (_: Exception) {}
            try { old.release() } catch (_: Exception) {}
        }
        setState(next)
    }

    private fun status(): Map<String, Any> {
        val remaining = (60_000L - (SystemClock.elapsedRealtime() - openingAt)).coerceAtLeast(0)
        val idle = (30_000L - (SystemClock.elapsedRealtime() - idleAt)).coerceAtLeast(0)
        val wall = System.currentTimeMillis()
        return mapOf("state" to state, "expiresAt" to wall + remaining, "idleExpiresAt" to wall + idle)
    }

    private fun setState(next: String) {
        state = next
        val event = if (next == "closed" || next == "error") mapOf("state" to next) else status()
        val token = generation.get()
        main.post { if (generation.get() == token && state == next) emit(event) }
    }

    private fun discardReference(metadata: Map<String, Any>) {
        val reference = metadata["reference"] as? String ?: return
        try { store.delete(reference) } catch (_: Exception) { setState("error") }
    }

    private fun reply(
        callback: (Map<String, Any>?, String?) -> Unit,
        value: Map<String, Any>?,
        code: String?,
        ticket: VisionLifecycleFence.Ticket? = null,
    ) {
        main.post {
            if (ticket == null) {
                callback(value, code)
            } else {
                val delivered = ticket.deliver(guard() == null, code) { finalCode ->
                    if (finalCode != null && value?.containsKey("reference") == true)
                        worker.post { discardReference(value) }
                    callback(if (finalCode == null) value else null, finalCode)
                }
                if (!delivered && value?.containsKey("reference") == true)
                    worker.post { discardReference(value) }
            }
        }
    }
}
