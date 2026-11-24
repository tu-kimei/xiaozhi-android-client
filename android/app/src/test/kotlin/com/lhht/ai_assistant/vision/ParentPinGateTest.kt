package com.lhht.ai_assistant.vision

import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.*
import org.junit.Test

class ParentPinGateTest {
    private val fakeDerivation = object : PinDerivation {
        override fun randomSalt() = ByteArray(32) { 17 }
        override fun derive(pin: CharArray, salt: ByteArray): ByteArray =
            MessageDigest.getInstance("SHA-256").digest(salt + String(pin).toByteArray())
    }

    @Test fun noDefaultPinAndOneUseAuthorization() {
        val dir = Files.createTempDirectory("pin-test").toFile()
        try {
            val file = dir.resolve("record")
            val gate = ParentPinGate(PrivatePinRecords(file), fakeDerivation, { 1000L }, { 2000L })
            assertFalse(gate.configured())
            assertFalse(gate.consume()) // setConsent(true) must reject
            gate.enroll("123456")
            assertTrue(gate.configured())
            assertFalse(file.readText().contains("123456"))
            assertFalse(gate.consume())
            gate.authorize("123456")
            assertTrue(gate.consume())
            assertFalse(gate.consume())
            gate.authorize("123456")
            gate.revoke() // pause/screen-off/close
            assertFalse(gate.consume())
        } finally { dir.deleteRecursively() }
    }

    @Test fun persistedFailuresSurviveRestartAndPinChangeRequiresCurrent() {
        val dir = Files.createTempDirectory("pin-test").toFile()
        try {
            val records = PrivatePinRecords(dir.resolve("record"))
            var wall = 100_000L
            var elapsed = 10L
            fun gate() = ParentPinGate(records, fakeDerivation, { wall }, { elapsed })
            gate().enroll("123456")
            repeat(3) {
                try { gate().authorize("000000"); fail("wrong PIN accepted") }
                catch (failure: VisionFailure) { assertEquals("pin_invalid", failure.code) }
            }
            try { gate().authorize("123456"); fail("lock lost after restart") }
            catch (failure: VisionFailure) { assertEquals("pin_locked", failure.code) }
            wall += 30_001
            try { gate().enroll("987654"); fail("changed without current PIN") }
            catch (failure: VisionFailure) { assertEquals("pin_required", failure.code) }
            gate().enroll("987654", "123456")
            elapsed += 1
            val reopened = gate()
            reopened.authorize("987654")
            assertTrue(reopened.consume())
        } finally { dir.deleteRecursively() }
    }

    @Test fun corruptRecordNeverBecomesFirstEnrollment() {
        val dir = Files.createTempDirectory("pin-test").toFile()
        try {
            val file = dir.resolve("record")
            file.writeText("corrupt")
            val gate = ParentPinGate(PrivatePinRecords(file), fakeDerivation, { 0L }, { 0L })
            try { gate.enroll("123456"); fail("corrupt record was silently reset") }
            catch (failure: VisionFailure) { assertEquals("pin_storage", failure.code) }
        } finally { dir.deleteRecursively() }
    }

    @Test fun authorizationExpiresAndClockRollbackCannotClearPersistedLock() {
        val dir = Files.createTempDirectory("pin-test").toFile()
        try {
            val records = PrivatePinRecords(dir.resolve("record"))
            var wall = 100_000L
            var elapsed = 10L
            val gate = ParentPinGate(records, fakeDerivation, { wall }, { elapsed })
            gate.enroll("123456")
            gate.authorize("123456")
            elapsed += 90_001L
            assertFalse(gate.consume())
            repeat(3) {
                try { gate.authorize("000000"); fail("wrong PIN accepted") }
                catch (_: VisionFailure) {}
            }
            wall -= 50_000L
            try { ParentPinGate(records, fakeDerivation, { wall }, { elapsed }).authorize("123456"); fail("rollback cleared lock") }
            catch (failure: VisionFailure) { assertEquals("pin_locked", failure.code) }
        } finally { dir.deleteRecursively() }
    }

    @Test fun revokeNeverWaitsForSlowKdfAndCannotMintLateGrant() {
        val dir = Files.createTempDirectory("pin-test").toFile()
        try {
            val entered = CountDownLatch(1)
            val continueKdf = CountDownLatch(1)
            var block = false
            val derivation = object : PinDerivation {
                override fun randomSalt() = ByteArray(32)
                override fun derive(pin: CharArray, salt: ByteArray): ByteArray {
                    if (block) {
                        entered.countDown()
                        check(continueKdf.await(3, TimeUnit.SECONDS))
                    }
                    return MessageDigest.getInstance("SHA-256").digest(salt + String(pin).toByteArray())
                }
            }
            val gate = ParentPinGate(PrivatePinRecords(dir.resolve("record")), derivation, { 1L }, { 1L })
            gate.enroll("123456")
            block = true
            var result: String? = null
            val worker = Thread {
                try { gate.authorize("123456") }
                catch (failure: VisionFailure) { result = failure.code }
            }.also { it.start() }
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            val start = System.nanoTime()
            gate.revoke()
            assertTrue("revoke blocked behind KDF", System.nanoTime() - start < 500_000_000L)
            continueKdf.countDown()
            worker.join(3000)
            assertFalse(worker.isAlive)
            assertEquals("cancelled", result)
            assertFalse(gate.consume())
        } finally { dir.deleteRecursively() }
    }

    @Test fun lostKeystoreKeyWithExistingRecordNeverRegenerates() {
        val dir = Files.createTempDirectory("pin-test").toFile()
        try {
            val derivation = object : KeystorePinDerivation() {
                var key: SecretKey? = null
                var creations = 0
                override fun existingKey(): SecretKey? = key
                override fun createKey(): SecretKey {
                    creations++
                    return SecretKeySpec(ByteArray(32) { 42 }, "HmacSHA256").also { key = it }
                }
            }
            val records = PrivatePinRecords(dir.resolve("record"))
            val gate = ParentPinGate(records, derivation, { 1L }, { 1L })
            gate.enroll("123456") // first enrollment is the only key creation
            assertEquals(1, derivation.creations)
            val original = records.read()!!.verifier.clone()
            derivation.key = null // simulated KeyStore loss with intact verifier
            try { gate.authorize("123456"); fail("lost key accepted") }
            catch (failure: VisionFailure) { assertEquals("pin_storage", failure.code) }
            try { gate.enroll("987654", "123456"); fail("re-enrolled under a new key") }
            catch (failure: VisionFailure) { assertEquals("pin_storage", failure.code) }
            assertEquals(1, derivation.creations)
            assertArrayEquals(original, records.read()!!.verifier)
            assertFalse(gate.consume())
        } finally { dir.deleteRecursively() }
    }
}
