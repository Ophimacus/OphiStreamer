package com.ophistreamer.tester

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.net.wifi.WifiManager
import android.os.Build
import android.view.Display
import android.view.InputDevice
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

data class DecoderInfo(
    val label: String,
    val codecName: String?,
    val hardware: Boolean,
    /** Highest of 120/90/60/30 fps the decoder reports for 1280x720, 0 if none. */
    val maxFps720: Int,
    val maxFps1080: Int,
)

data class ScreenInfo(val widthPx: Int, val heightPx: Int, val maxRefreshHz: Int)

data class ControllerInfo(
    val name: String,
    val vendorId: Int,
    val productId: Int,
    val external: Boolean,
    val vibrates: Boolean,
)

data class MoonlightAdvice(
    val resolution: String,
    val fps: Int,
    val codec: String,
    val bitrateMbps: Int,
    val tryLater: String?,
)

object DeviceProbe {
    private val CODECS = listOf(
        "video/hevc" to "H.265 (HEVC)",
        "video/avc" to "H.264",
        "video/av01" to "AV1",
    )

    fun decoders(): List<DecoderInfo> {
        val all = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder }
        return CODECS.map { (mime, label) ->
            val candidates = all.filter { info -> info.supportedTypes.any { it.equals(mime, ignoreCase = true) } }
            val best = candidates.firstOrNull { isHardware(it) } ?: candidates.firstOrNull()
            if (best == null) {
                DecoderInfo(label, null, false, 0, 0)
            } else {
                val video = best.getCapabilitiesForType(mime).videoCapabilities
                DecoderInfo(label, best.name, isHardware(best), maxFps(video, 1280, 720), maxFps(video, 1920, 1080))
            }
        }
    }

    fun screen(context: Context): ScreenInfo {
        val display = context.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        val modes = display.supportedModes
        val mode = display.mode
        return ScreenInfo(
            widthPx = max(mode.physicalWidth, mode.physicalHeight),
            heightPx = min(mode.physicalWidth, mode.physicalHeight),
            maxRefreshHz = modes.maxOf { it.refreshRate }.roundToInt(),
        )
    }

    /** Gamepads Android can see (USB-C or Bluetooth), one entry per physical device. */
    @Suppress("DEPRECATION")
    fun controllers(): List<ControllerInfo> =
        InputDevice.getDeviceIds().toList()
            .mapNotNull { InputDevice.getDevice(it) }
            .filter { d ->
                (d.sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
                    (d.sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
            }
            .map { d ->
                ControllerInfo(
                    name = d.name,
                    vendorId = d.vendorId,
                    productId = d.productId,
                    external = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) d.isExternal else true,
                    vibrates = d.vibrator.hasVibrator(),
                )
            }
            .distinctBy { Triple(it.name, it.vendorId, it.productId) }

    /** A safe starting point for Moonlight on this phone, plus what to try once that is smooth. */
    fun advice(screen: ScreenInfo, decoders: List<DecoderInfo>): MoonlightAdvice {
        val hevc = decoders.first { it.label.startsWith("H.265") }
        val avc = decoders.first { it.label == "H.264" }
        val use1080 = screen.heightPx >= 1080
        val codec = if (hevc.hardware && (if (use1080) hevc.maxFps1080 else hevc.maxFps720) >= 60) hevc else avc
        val codecMax = if (use1080) codec.maxFps1080 else codec.maxFps720
        val higherFps = listOf(120, 90).firstOrNull { it <= screen.maxRefreshHz && it <= codecMax }
        val baseMbps = if (use1080) 20 else 10
        val bitrate = if (codec === avc) (baseMbps * 1.5).roundToInt() else baseMbps
        return MoonlightAdvice(
            resolution = if (use1080) "1920×1080" else "1280×720",
            fps = 60,
            codec = codec.label,
            bitrateMbps = bitrate,
            tryLater = higherFps?.let { "$it fps at ${bitrate + bitrate / 2} Mbps once 60 fps is smooth" },
        )
    }

    /** Hold the same Wi-Fi locks Moonlight holds while streaming, so the test sees the same radio behaviour. */
    @Suppress("DEPRECATION")
    fun acquireStreamingWifiLocks(context: Context): List<WifiManager.WifiLock> {
        val wm = context.applicationContext.getSystemService(WifiManager::class.java)
        val locks = mutableListOf(wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "OphiStreamer High Perf"))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            locks += wm.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "OphiStreamer Low Latency")
        }
        for (lock in locks) {
            lock.setReferenceCounted(false)
            try {
                lock.acquire()
            } catch (_: SecurityException) {
                // Some vendor builds throw here (Moonlight works around the same thing).
            }
        }
        return locks
    }

    fun release(locks: List<WifiManager.WifiLock>) {
        for (lock in locks) if (lock.isHeld) lock.release()
    }

    private fun isHardware(info: MediaCodecInfo): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            info.isHardwareAccelerated
        } else {
            !info.name.startsWith("OMX.google.") && !info.name.startsWith("c2.android.")
        }

    private fun maxFps(video: MediaCodecInfo.VideoCapabilities?, w: Int, h: Int): Int =
        listOf(120, 90, 60, 30).firstOrNull { video?.areSizeAndRateSupported(w, h, it.toDouble()) == true } ?: 0
}
