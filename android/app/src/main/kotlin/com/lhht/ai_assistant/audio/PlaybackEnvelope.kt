package com.lhht.ai_assistant.audio

import java.util.ArrayDeque
import kotlin.math.sqrt

/** Small RMS windows aligned with AudioTrack frame positions. No audio copies. */
internal class PlaybackEnvelope {
    private data class Window(val start: Long, val end: Long, val level: Double)
    private val windows = ArrayDeque<Window>()

    @Synchronized fun append(data: ByteArray, start: Long, sampleRate: Int) {
        val frames = data.size / 2
        val windowFrames = (sampleRate / 50).coerceAtLeast(1)
        var offset = 0
        while (offset < frames) {
            val end = (offset + windowFrames).coerceAtMost(frames)
            var sum = 0.0
            for (i in offset until end) {
                val sample = ((data[i * 2].toInt() and 255) or
                    (data[i * 2 + 1].toInt() shl 8)).toShort().toDouble() / 32768.0
                sum += sample * sample
            }
            val rms = sqrt(sum / (end - offset))
            // Ignore the noise floor; speech should use the full mouth range.
            val level = if (rms < 0.008) 0.0 else (sqrt(rms) * 2).coerceAtMost(1.0)
            windows.add(Window(start + offset, start + end, level))
            offset = end
        }
        while (windows.size > 2048) windows.removeFirst()
    }

    @Synchronized fun levelAt(frame: Long): Double {
        while (windows.isNotEmpty() && windows.first.end <= frame) windows.removeFirst()
        val current = windows.peekFirst() ?: return 0.0
        return if (frame >= current.start && frame < current.end) current.level else 0.0
    }

    @Synchronized fun clear() = windows.clear()
}
