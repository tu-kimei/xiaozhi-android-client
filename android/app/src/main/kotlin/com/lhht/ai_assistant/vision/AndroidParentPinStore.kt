package com.lhht.ai_assistant.vision

import android.content.Context
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

internal fun createParentPinGate(context: Context): ParentPinGate {
    val records = PrivatePinRecords(File(context.noBackupFilesDir, "vision-parent-pin-v1"))
    return ParentPinGate(records, KeystorePinDerivation(), System::currentTimeMillis, SystemClock::elapsedRealtime)
}

/** Atomic app-private record, excluded from Android auto-backup. Corruption fails closed. */
internal class PrivatePinRecords(private val file: File) : PinRecords {
    override fun read(): PinRecord? {
        if (!file.exists()) return null
        try {
            val fields = file.readText(Charsets.US_ASCII).trim().split(':')
            if (fields.size != 6 || fields[0] != "v1") throw IllegalArgumentException()
            val salt = decodeHex(fields[1])
            val verifier = decodeHex(fields[2])
            if (salt.size != 32 || verifier.size != 32) throw IllegalArgumentException()
            val failures = fields[3].toInt()
            val locked = fields[4].toLong()
            val last = fields[5].toLong()
            if (failures < 0 || locked < 0 || last < 0) throw IllegalArgumentException()
            return PinRecord(salt, verifier, failures, locked, last)
        } catch (_: Exception) { throw VisionFailure("pin_storage") }
    }

    override fun write(record: PinRecord) {
        val temp = File(file.parentFile, "${file.name}.tmp")
        try {
            val data = listOf(
                "v1", record.salt.joinToString("") { "%02x".format(it) },
                record.verifier.joinToString("") { "%02x".format(it) },
                record.failures, record.lockedUntilWall, record.lastWall,
            ).joinToString(":")
            FileOutputStream(temp).use { it.write(data.toByteArray(Charsets.US_ASCII)); it.fd.sync() }
            if (!temp.renameTo(file)) throw IllegalStateException()
        } catch (_: Exception) { throw VisionFailure("pin_storage") }
        finally { temp.delete() }
    }

    private fun decodeHex(value: String): ByteArray {
        if (!value.matches(Regex("[0-9a-f]{64}"))) throw IllegalArgumentException()
        return ByteArray(32) { index -> value.substring(index * 2, index * 2 + 2).toInt(16).toByte() }
    }
}

/** PBKDF2 slows guessing; non-exportable AndroidKeyStore HMAC key peppers the persisted verifier. */
internal open class KeystorePinDerivation : PinDerivation {
    private val random = SecureRandom()
    override fun randomSalt() = ByteArray(32).also(random::nextBytes)

    /** Create the pepper only for first enrollment; never regenerate for an existing record. */
    override fun ensureKey() {
        try {
            if (existingKey() == null) createKey()
        } catch (_: Exception) {
            throw VisionFailure("pin_storage")
        }
    }

    override fun derive(pin: CharArray, salt: ByteArray): ByteArray {
        try {
            val spec = PBEKeySpec(pin, salt, 210_000, 256)
            val stretched = try {
                SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
            } finally { spec.clearPassword(); pin.fill('\u0000') }
            try {
                val key = existingKey() ?: throw VisionFailure("pin_storage")
                return Mac.getInstance("HmacSHA256").run { init(key); doFinal(stretched) }
            } finally { stretched.fill(0) }
        } catch (_: Exception) { throw VisionFailure("pin_storage") }
    }

    protected open fun existingKey(): SecretKey? =
        (KeyStore.getInstance("AndroidKeyStore").also { it.load(null) }).getKey(ALIAS, null) as? SecretKey

    protected open fun createKey(): SecretKey =
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                .setDigests(KeyProperties.DIGEST_SHA256).build())
            generateKey()
        }

    companion object { private const val ALIAS = "visbot_vision_parent_pin_v1" }
}
