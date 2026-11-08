package com.lhht.ai_assistant.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Streaming PCM16 mono player for TTS replies.
 *
 * Replaces flutter_pcm_player, whose AudioTrack only had the minimum buffer
 * and whose writer ran at normal priority: any CPU hiccup (opus decode, UI,
 * mic) starved the track and the voice stuttered. Like the stock Xiaozhi app
 * on the robot, this uses a 4x buffer and an URGENT_AUDIO writer thread.
 */
class PcmStreamPlayer(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "xiaozhi/pcm_player")
    private val queue = LinkedBlockingQueue<ByteArray>()
    private val lock = Object()

    @Volatile private var track: AudioTrack? = null
    @Volatile private var running = true
    private var underruns = 0

    private val writer = Thread({
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        while (running) {
            val data = try {
                queue.poll(200, TimeUnit.MILLISECONDS)
            } catch (e: InterruptedException) {
                null
            }
            if (data == null) {
                // Nothing to play: stop() lets what is buffered finish, then
                // idles the track. Left "playing" on an empty queue, Android
                // disables it after the underrun and the restart clips the
                // start of the next reply.
                synchronized(lock) {
                    val t = track
                    if (t != null && t.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        t.stop()
                    }
                }
                continue
            }
            synchronized(lock) {
                val t = track ?: return@synchronized
                var offset = 0
                if (t.playState != AudioTrack.PLAYSTATE_PLAYING) {
                    // Prime the buffer before starting, otherwise the track
                    // starts empty and underruns right away.
                    offset = t.write(data, 0, data.size, AudioTrack.WRITE_NON_BLOCKING)
                        .coerceAtLeast(0)
                    t.play()
                }
                if (offset < data.size) {
                    t.write(data, offset, data.size - offset, AudioTrack.WRITE_BLOCKING)
                }
                val u = t.underrunCount
                if (u != underruns) {
                    Log.w(TAG, "AudioTrack underrun count $u, queued ${queue.size}")
                    underruns = u
                }
            }
        }
    }, "xiaozhi-pcm-writer")

    init {
        channel.setMethodCallHandler(this)
        writer.start()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    initialize(call.argument<Int>("sampleRate") ?: 24000)
                    result.success(null)
                }
                "feed" -> {
                    call.argument<ByteArray>("data")?.let { queue.offer(it) }
                    result.success(null)
                }
                "play" -> {
                    synchronized(lock) { track?.play() }
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "release" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("pcm_player", e.message, null)
        }
    }

    private fun initialize(sampleRate: Int) {
        release()
        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(minBuf * 4)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        synchronized(lock) {
            track = t
            underruns = 0
        }
        Log.i(TAG, "init ${sampleRate}Hz buffer ${minBuf * 4} bytes (min $minBuf)")
    }

    /** Interrupt: drop everything queued and in the track, keep the track. */
    private fun stop() {
        queue.clear()
        synchronized(lock) {
            track?.let {
                it.pause()
                it.flush()
                it.play()
            }
        }
    }

    private fun release() {
        queue.clear()
        synchronized(lock) {
            track?.let {
                try {
                    it.stop()
                } catch (_: IllegalStateException) {
                }
                it.release()
            }
            track = null
        }
    }

    fun dispose() {
        running = false
        writer.interrupt()
        release()
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val TAG = "PcmStreamPlayer"
    }
}
