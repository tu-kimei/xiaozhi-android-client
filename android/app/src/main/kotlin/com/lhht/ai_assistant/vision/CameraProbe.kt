package com.lhht.ai_assistant.vision

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.Camera
import android.util.Log
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Stage-0 diagnostic for the Visbot's legacy Camera API1 HAL.
 *
 * The Visbot MTK HAL only publishes `API1 info` (`API2 not directly supported`).
 * Preview frames must be consumed, otherwise the buffer queue stalls and the
 * HAL never completes `takePicture()`. This probe uses
 * `setPreviewCallbackWithBuffer` (no GL context needed), then captures one JPEG
 * per variant to measure capture latency, JPEG size and real pixel dimensions.
 * Every artifact is deleted immediately; nothing is uploaded.
 */
class CameraProbe(
    private val context: Context,
    private val keepArtifacts: Boolean = false,
) {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    private data class Variant(val label: String, val width: Int, val height: Int, val rotation: Int)

    fun run() {
        executor.execute {
            var camera: Camera? = null
            try {
                val info = Camera.CameraInfo()
                Camera.getCameraInfo(DEFAULT_CAMERA_ID, info)
                Log.i(TAG, "probe start id=$DEFAULT_CAMERA_ID facing=${info.facing} orientation=${info.orientation}")

                camera = Camera.open(DEFAULT_CAMERA_ID)
                val supportedPictures = camera.parameters.supportedPictureSizes
                Log.i(TAG, "probe supported pictures=${supportedPictures.joinToString { "${it.width}x${it.height}" }}")

                for (variant in plan(info.orientation, supportedPictures)) {
                    if (!variant.isSupportedBy(supportedPictures)) {
                        Log.w(TAG, "variant ${variant.label} skipped unsupported ${variant.width}x${variant.height}")
                        continue
                    }
                    measure(camera, info, variant)
                }
            } catch (error: Throwable) {
                Log.e(TAG, "probe failed type=${error.javaClass.simpleName} message=${error.message}", error)
            } finally {
                try {
                    camera?.setPreviewCallbackWithBuffer(null)
                } catch (_: Throwable) {
                }
                try {
                    camera?.stopPreview()
                } catch (_: Throwable) {
                }
                try {
                    camera?.release()
                } catch (_: Throwable) {
                }
                Log.i(TAG, "probe finished")
            }
        }
    }

    fun dispose() {
        executor.shutdownNow()
    }

    private fun measure(camera: Camera, info: Camera.CameraInfo, variant: Variant) {
        var probeFile: File? = null
        try {
            camera.stopPreview()

            val parameters = camera.parameters
            val preview = choosePreviewSize(parameters.supportedPreviewSizes, variant)
            parameters.setPictureSize(variant.width, variant.height)
            parameters.setPreviewSize(preview.width, preview.height)
            parameters.previewFormat = ImageFormat.NV21
            parameters.jpegQuality = JPEG_QUALITY
            parameters.setRotation(variant.rotation)
            camera.parameters = parameters

            val frameCount = AtomicInteger(0)
            val firstFrame = CountDownLatch(1)
            val bufferSize = previewBufferSize(preview, parameters.previewFormat)
            repeat(PREVIEW_BUFFER_COUNT) { camera.addCallbackBuffer(ByteArray(bufferSize)) }
            camera.setPreviewCallbackWithBuffer { data, active ->
                frameCount.incrementAndGet()
                firstFrame.countDown()
                if (data != null) active.addCallbackBuffer(data)
            }

            val previewStartedAt = System.currentTimeMillis()
            camera.startPreview()
            val gotFrame = firstFrame.await(PREVIEW_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            val firstFrameMs = System.currentTimeMillis() - previewStartedAt
            Thread.sleep(PREVIEW_WARMUP_MS)
            val framesBeforeCapture = frameCount.get()
            val previewMs = System.currentTimeMillis() - previewStartedAt
            Log.i(
                TAG,
                "variant ${variant.label} preview=${preview.width}x${preview.height} firstFrame=$gotFrame " +
                    "firstFrameMs=$firstFrameMs fps=${rate(framesBeforeCapture, previewMs)}",
            )
            if (!gotFrame) {
                Log.w(TAG, "variant ${variant.label} no preview frame, skipping capture")
                return
            }

            val captureStartedAt = System.currentTimeMillis()
            val jpeg = capture(camera)
            val captureMs = System.currentTimeMillis() - captureStartedAt

            probeFile = File.createTempFile("camera-probe-", ".jpg", context.cacheDir)
            probeFile.writeBytes(jpeg)
            val sof = jpegPixelSize(jpeg)
            val exif = exifOrientation(probeFile)
            if (keepArtifacts) {
                val keepDir = context.getExternalFilesDir(null) ?: context.cacheDir
                val kept = File(keepDir, "probe-${variant.label}.jpg")
                kept.delete()
                if (!probeFile.renameTo(kept)) {
                    kept.writeBytes(jpeg)
                    probeFile.delete()
                }
                Log.i(TAG, "variant ${variant.label} kept=${kept.absolutePath}")
            } else {
                Log.i(TAG, "variant ${variant.label} artifact deleted=${probeFile.delete()}")
            }
            probeFile = null
            Log.i(
                TAG,
                "variant ${variant.label} rotation=${variant.rotation} captureMs=$captureMs bytes=${jpeg.size} " +
                    "sof=${sof.first}x${sof.second} exif=$exif expected=${expectedPixels(variant, info.orientation)}",
            )
        } catch (error: Throwable) {
            Log.e(TAG, "variant ${variant.label} failed type=${error.javaClass.simpleName} message=${error.message}", error)
        } finally {
            try {
                camera.setPreviewCallbackWithBuffer(null)
            } catch (_: Throwable) {
            }
            try {
                camera.stopPreview()
            } catch (_: Throwable) {
            }
            if (probeFile?.delete() == false) {
                Log.w(TAG, "probe artifact cleanup failed")
            }
        }
    }

    private fun capture(camera: Camera): ByteArray {
        val result = AtomicReference<ByteArray?>()
        val done = CountDownLatch(1)
        camera.takePicture(null, null) { data, _ ->
            result.set(data)
            done.countDown()
        }
        if (!done.await(CAPTURE_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
            throw IllegalStateException("takePicture timeout after ${CAPTURE_TIMEOUT_MS}ms")
        }
        return result.get() ?: error("takePicture returned no data")
    }

    /**
     * Variant matrix: measure the cost of HAL rotation and of picture size.
     * `rotation` is the value passed to `Camera.Parameters.setRotation`.
     */
    private fun plan(sensorOrientation: Int, supported: List<Camera.Size>): List<Variant> {
        val back = sensorOrientation
        val candidates = if (keepArtifacts) {
            // Only the two orientation candidates are kept, for visual inspection.
            listOf(
                Variant("640x480-rot0", 640, 480, 0),
                Variant("640x480-rot$back", 640, 480, back),
            )
        } else {
            listOf(
                Variant("640x480-rot0", 640, 480, 0),
                Variant("640x480-rot$back", 640, 480, back),
                Variant("640x480-rot0-warm", 640, 480, 0),
                Variant("320x240-rot0", 320, 240, 0),
                Variant("1280x720-rot0", 1280, 720, 0),
            )
        }
        return candidates.filter { it.isSupportedBy(supported) }
    }

    private fun Variant.isSupportedBy(sizes: List<Camera.Size>): Boolean =
        sizes.any { it.width == width && it.height == height }

    private fun expectedPixels(variant: Variant, sensorOrientation: Int): String {
        val rotated = variant.rotation % 180 != 0
        return if (rotated) "${variant.height}x${variant.width}" else "${variant.width}x${variant.height}"
    }

    private fun rate(frames: Int, windowMs: Long): Float {
        if (windowMs <= 0) return 0f
        return frames * 1000f / windowMs
    }

    private fun exifOrientation(file: File): Int {
        return try {
            val exif = android.media.ExifInterface(file.absolutePath)
            exif.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, -1)
        } catch (error: Throwable) {
            Log.w(TAG, "exif read failed: ${error.javaClass.simpleName}")
            -1
        }
    }

    private fun previewBufferSize(size: Camera.Size, format: Int): Int {
        val bits = ImageFormat.getBitsPerPixel(format).let { if (it <= 0) 12 else it }
        return size.width * size.height * bits / 8
    }

    private fun choosePreviewSize(sizes: List<Camera.Size>, variant: Variant): Camera.Size {
        return sizes.firstOrNull { it.width == variant.width && it.height == variant.height }
            ?: sizes.firstOrNull { it.width == 640 && it.height == 480 }
            ?: sizes.minByOrNull { it.width.toLong() * it.height.toLong() }
            ?: throw IllegalStateException("camera has no supported preview size")
    }

    /** Reads the JPEG SOF marker, which is the authoritative pixel size. */
    private fun jpegPixelSize(jpeg: ByteArray): Pair<Int, Int> {
        var index = 2
        while (index + 9 < jpeg.size) {
            if (jpeg[index].toInt() and 0xFF != 0xFF) {
                index++
                continue
            }
            val marker = jpeg[index + 1].toInt() and 0xFF
            if (marker == 0xD8 || marker == 0xD9 || marker in 0xD0..0xD7 || marker == 0x01) {
                index += 2
                continue
            }
            val length = ((jpeg[index + 2].toInt() and 0xFF) shl 8) or (jpeg[index + 3].toInt() and 0xFF)
            val isSof = marker in 0xC0..0xC3 || marker in 0xC5..0xC7 || marker in 0xC9..0xCB || marker in 0xCD..0xCF
            if (isSof) {
                val height = ((jpeg[index + 5].toInt() and 0xFF) shl 8) or (jpeg[index + 6].toInt() and 0xFF)
                val width = ((jpeg[index + 7].toInt() and 0xFF) shl 8) or (jpeg[index + 8].toInt() and 0xFF)
                return width to height
            }
            index += 2 + length
        }
        return 0 to 0
    }

    companion object {
        private const val TAG = "VisbotCameraProbe"
        private const val DEFAULT_CAMERA_ID = 0
        private const val JPEG_QUALITY = 85
        private const val PREVIEW_BUFFER_COUNT = 3
        private const val PREVIEW_TIMEOUT_MS = 5000L
        private const val PREVIEW_WARMUP_MS = 1200L
        private const val CAPTURE_TIMEOUT_MS = 15000L
    }
}
