package com.lhht.ai_assistant.vision

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Clock/generation policy independent of Android and the camera HAL. */
internal class VisionLifecycleFence(
    private val elapsed: () -> Long,
    private val generation: AtomicLong = AtomicLong(),
) {

    fun current(): Long = generation.get()
    fun advance(): Long = generation.incrementAndGet()
    fun advanceIf(expected: Long): Boolean = generation.compareAndSet(expected, expected + 1)
    fun valid(token: Long, deadline: Long = Long.MAX_VALUE): Boolean =
        current() == token && elapsed() < deadline

    fun reason(token: Long, deadline: Long, allowed: Boolean): String? = when {
        elapsed() >= deadline -> "timeout"
        current() != token || !allowed -> "cancelled"
        else -> null
    }

    /** Claim and evaluate at actual delivery, never when a worker merely posts a result. */
    inner class Ticket(val token: Long, val deadline: Long = Long.MAX_VALUE) {
        private val finished = AtomicBoolean(false)

        fun deliver(allowed: Boolean, requestedCode: String?, receiver: (String?) -> Unit): Boolean {
            if (!finished.compareAndSet(false, true)) return false
            receiver(reason(token, deadline, allowed) ?: requestedCode)
            return true
        }

        fun isFinished(): Boolean = finished.get()
    }
}
