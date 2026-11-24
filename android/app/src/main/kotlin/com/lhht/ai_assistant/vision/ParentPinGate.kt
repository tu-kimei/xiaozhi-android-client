package com.lhht.ai_assistant.vision

import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicLong

internal data class PinRecord(
    val salt: ByteArray,
    val verifier: ByteArray,
    val failures: Int = 0,
    val lockedUntilWall: Long = 0,
    val lastWall: Long = 0,
)

internal interface PinRecords {
    fun read(): PinRecord?
    fun write(record: PinRecord)
}

internal interface PinDerivation {
    fun randomSalt(): ByteArray
    fun derive(pin: CharArray, salt: ByteArray): ByteArray
    /** Called only for first enrollment, before any record exists. */
    fun ensureKey() {}
}

/** Native-only session authorization. No PIN or verifier is returned through Flutter. */
internal class ParentPinGate(
    private val records: PinRecords,
    private val derivation: PinDerivation,
    private val wall: () -> Long,
    private val elapsed: () -> Long,
) {
    // The slow KDF and the authorization grant use separate locks so a lifecycle
    // revoke never waits behind an in-progress PIN verification.
    private val pinLock = Any()
    private val grantLock = Any()
    private val generation = AtomicLong()
    private var authorizedUntil = 0L

    fun configured(): Boolean = records.read() != null

    fun enroll(newPin: String, currentPin: String? = null) {
        synchronized(pinLock) {
            validate(newPin)
            val prior = records.read()
            if (prior != null) {
                if (currentPin == null) throw VisionFailure("pin_required")
                verifyLocked(currentPin)
            } else {
                if (currentPin != null) throw VisionFailure("pin_not_configured")
                derivation.ensureKey()
            }
            val salt = derivation.randomSalt()
            val digest = derivation.derive(newPin.toCharArray(), salt)
            records.write(PinRecord(salt, digest, lastWall = wall()))
        }
        revoke()
    }

    fun authorize(pin: String) {
        val token = synchronized(grantLock) { generation.get() }
        verify(pin)
        val deadline = elapsed() + 90_000L
        synchronized(grantLock) {
            if (generation.get() != token) throw VisionFailure("cancelled")
            authorizedUntil = deadline
        }
    }

    /** One successful PIN check permits exactly one 60-second camera window. */
    fun consume(): Boolean = synchronized(grantLock) {
        val allowed = authorizedUntil > 0L && elapsed() < authorizedUntil
        authorizedUntil = 0L
        allowed
    }

    /** Non-blocking revocation: never takes [pinLock] or waits for the KDF. */
    fun revoke() = synchronized(grantLock) {
        generation.incrementAndGet()
        authorizedUntil = 0L
    }

    fun authorized(): Boolean = synchronized(grantLock) {
        authorizedUntil > 0L && elapsed() < authorizedUntil
    }

    private fun validate(pin: String) {
        if (!pin.matches(Regex("[0-9]{6,12}"))) throw VisionFailure("invalid_pin")
    }

    private fun verify(pin: String) = synchronized(pinLock) { verifyLocked(pin) }

    private fun verifyLocked(pin: String) {
        val record = records.read() ?: throw VisionFailure("pin_not_configured")
        val now = maxOf(wall(), record.lastWall)
        if (now < record.lockedUntilWall) throw VisionFailure("pin_locked")
        val derived = derivation.derive(pin.toCharArray(), record.salt)
        if (!MessageDigest.isEqual(derived, record.verifier)) {
            val failures = (record.failures + 1).coerceAtMost(1000)
            val delay = if (failures < 3) 0L else (30_000L * (1L shl (failures - 3).coerceAtMost(7))).coerceAtMost(3_600_000L)
            records.write(record.copy(failures = failures, lockedUntilWall = now + delay, lastWall = now))
            revoke()
            throw VisionFailure("pin_invalid")
        }
        records.write(record.copy(failures = 0, lockedUntilWall = 0, lastWall = now))
    }
}
