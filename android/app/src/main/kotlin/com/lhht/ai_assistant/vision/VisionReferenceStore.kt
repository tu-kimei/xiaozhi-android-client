package com.lhht.ai_assistant.vision

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.security.SecureRandom

/** Private, non-backed-up, opaque references. No public path or byte resolver exists yet. */
internal class VisionReferenceStore(private val directory: File, private val now: () -> Long = System::currentTimeMillis) {
    constructor(context: Context) : this(File(context.noBackupFilesDir, "vision-snapshots"))

    private val random = SecureRandom()
    private val retained = mutableMapOf<String, Long>()

    init {
        require(directory.isDirectory || directory.mkdirs()) { "store unavailable" }
        cleanupStale()
    }

    @Synchronized fun put(jpeg: ByteArray): Map<String, Any> {
        val dimensions = validateJpeg(jpeg) ?: throw VisionFailure("invalid_image")
        // Bound the store to one live artifact, even if Dart forgets to delete a reference.
        deleteAll()
        val tokenBytes = ByteArray(24).also(random::nextBytes)
        val token = tokenBytes.joinToString("") { "%02x".format(it) }
        val destination = File(directory, "$token.jpg")
        val temporary = File(directory, "$token.tmp")
        try {
            FileOutputStream(temporary).use {
                it.write(jpeg)
                it.fd.sync()
            }
            if (!temporary.renameTo(destination)) throw VisionFailure("storage_unavailable")
            val capturedAt = now()
            val expiresAt = capturedAt + TTL_MS
            retained[token] = expiresAt
            return mapOf(
                "reference" to token, "mimeType" to "image/jpeg",
                "width" to dimensions.first, "height" to dimensions.second,
                "bytes" to jpeg.size, "rotation" to 0,
                "capturedAt" to capturedAt, "expiresAt" to expiresAt, "canMove" to false,
            )
        } catch (_: Exception) {
            temporary.delete()
            destination.delete()
            throw VisionFailure("storage_unavailable")
        }
    }

    @Synchronized fun delete(reference: String) {
        // Never accept a path component supplied by a caller, even for deletion.
        if (!reference.matches(Regex("[0-9a-f]{48}"))) throw VisionFailure("invalid_argument")
        retained.remove(reference)
        val file = File(directory, "$reference.jpg")
        if (file.exists() && !file.delete()) throw VisionFailure("storage_unavailable")
    }

    @Synchronized fun deleteAll() {
        retained.clear()
        directory.listFiles()?.forEach { if (it.isFile && !it.delete()) throw VisionFailure("storage_unavailable") }
    }

    /** No reference survives a process restart: no authenticated native relay exists yet. */
    @Synchronized fun cleanupStale() {
        val time = now()
        retained.filterValues { it <= time }.keys.toList().forEach(::delete)
        directory.listFiles()?.forEach { file ->
            if (file.isFile && (file.extension != "jpg" || retained[file.nameWithoutExtension] == null)) {
                if (!file.delete()) throw VisionFailure("storage_unavailable")
            }
        }
    }

    companion object {
        const val TTL_MS = 60_000L
        const val MAX_BYTES = 2 * 1024 * 1024

        /** SOI/EOI plus a bounded SOF scan; never trust EXIF-reported dimensions. */
        fun validateJpeg(data: ByteArray): Pair<Int, Int>? {
            if (data.size !in 16..MAX_BYTES || (data[0].toInt() and 255) != 255 ||
                (data[1].toInt() and 255) != 216 ||
                (data[data.lastIndex - 1].toInt() and 255) != 255 ||
                (data.last().toInt() and 255) != 217) return null
            var i = 2
            while (i + 3 < data.size) {
                if ((data[i].toInt() and 255) != 255) return null
                val marker = data[i + 1].toInt() and 255
                if (marker == 217 || marker == 218) break
                if (marker == 1 || marker in 208..215) { i += 2; continue }
                val length = ((data[i + 2].toInt() and 255) shl 8) or (data[i + 3].toInt() and 255)
                if (length < 2 || i + 2 + length > data.size) return null
                if (marker in 192..195 || marker in 197..199 || marker in 201..203 || marker in 205..207) {
                    if (length < 7) return null
                    val height = ((data[i + 5].toInt() and 255) shl 8) or (data[i + 6].toInt() and 255)
                    val width = ((data[i + 7].toInt() and 255) shl 8) or (data[i + 8].toInt() and 255)
                    return if (width == 640 && height == 480) width to height else null
                }
                i += 2 + length
            }
            return null
        }
    }
}

internal class VisionFailure(val code: String) : RuntimeException()
