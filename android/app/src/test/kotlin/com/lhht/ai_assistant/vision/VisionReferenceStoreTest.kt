package com.lhht.ai_assistant.vision

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class VisionReferenceStoreTest {
    private fun jpeg(): ByteArray = byteArrayOf(
        0xff.toByte(), 0xd8.toByte(),
        0xff.toByte(), 0xc0.toByte(), 0, 17, 8, 1, 0xe0.toByte(), 2, 0x80.toByte(),
        3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0,
        0xff.toByte(), 0xd9.toByte(),
    )

    @Test fun validatesBoundsAndDimensions() {
        assertEquals(640 to 480, VisionReferenceStore.validateJpeg(jpeg()))
        assertNull(VisionReferenceStore.validateJpeg(jpeg().copyOfRange(0, jpeg().size - 1)))
        assertNull(VisionReferenceStore.validateJpeg(ByteArray(VisionReferenceStore.MAX_BYTES + 1)))
        val wrongSize = jpeg().clone().also { it[10] = 1 }
        assertNull(VisionReferenceStore.validateJpeg(wrongSize))
    }

    @Test fun privateReferencesDeleteAndExpire() {
        val directory = Files.createTempDirectory("vision-test").toFile()
        try {
            var now = 1000L
            val store = VisionReferenceStore(directory) { now }
            val first = store.put(jpeg())
            assertEquals(false, first["canMove"])
            assertEquals(60_000L, (first["expiresAt"] as Long) - (first["capturedAt"] as Long))
            assertEquals(1, directory.listFiles()!!.size)
            val token = first["reference"] as String
            store.delete(token)
            assertTrue(directory.listFiles()!!.isEmpty())
            store.put(jpeg())
            now += 60_001
            store.cleanupStale()
            assertTrue(directory.listFiles()!!.isEmpty())
            File(directory, "abandoned.tmp").writeText("partial")
            VisionReferenceStore(directory) { now }
            assertTrue(directory.listFiles()!!.isEmpty())
        } finally { directory.deleteRecursively() }
    }

    @Test fun rejectsPathsAndDeletesAllOnRevocation() {
        val directory = Files.createTempDirectory("vision-test").toFile()
        try {
            val store = VisionReferenceStore(directory)
            store.put(jpeg())
            try { store.delete("../escape"); fail("accepted a path") }
            catch (_: VisionFailure) {}
            store.deleteAll()
            assertTrue(directory.listFiles()!!.isEmpty())
        } finally { directory.deleteRecursively() }
    }
}
