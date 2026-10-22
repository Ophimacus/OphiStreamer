package com.ophistreamer.tester

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import java.io.IOException
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.URL
import java.util.UUID

data class WifiStatus(
    val connected: Boolean,
    val ssid: String? = null,
    val frequencyMhz: Int = 0,
    val rssiDbm: Int = 0,
    val linkMbps: Int = 0,
    val phoneIp: String? = null,
    val gateway: String? = null,
    /** Android only enables its low-latency Wi-Fi mode when the Wi-Fi network has validated internet. */
    val hasInternet: Boolean = false,
) {
    val band: String
        get() = when (frequencyMhz) {
            in 2400..2500 -> "2.4 GHz"
            in 4900..5900 -> "5 GHz"
            in 5925..7125 -> "6 GHz"
            else -> "unknown"
        }
}

class LatencyStats(samples: List<Double?>) {
    private val ok = samples.filterNotNull().sorted()
    val sent = samples.size
    val lost = samples.count { it == null }
    val avg = if (ok.isEmpty()) 0.0 else ok.average()
    val p99 = if (ok.isEmpty()) 0.0 else ok[minOf(ok.size - 1, (ok.size * 0.99).toInt())]
    val max = ok.lastOrNull() ?: 0.0
    val spikes = ok.count { it >= SPIKE_MS }

    companion object {
        const val SPIKE_MS = 50.0
    }
}

object NetProbe {
    /** Sunshine's TCP ports: HTTPS pairing, HTTP serverinfo, RTSP. */
    val SUNSHINE_TCP_PORTS = listOf(47984, 47989, 48010)
    const val SAMPLE_INTERVAL_MS = 200L
    private const val CONNECT_TIMEOUT_MS = 1000

    /** The Wi-Fi network, so traffic never leaks onto mobile data when the hotspot has no internet. */
    @Suppress("DEPRECATION")
    fun wifiNetwork(context: Context): Network? {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        return cm.allNetworks.firstOrNull {
            cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
    }

    @Suppress("DEPRECATION")
    fun wifiStatus(context: Context): WifiStatus {
        val net = wifiNetwork(context) ?: return WifiStatus(connected = false)
        val cm = context.getSystemService(ConnectivityManager::class.java)
        val wm = context.applicationContext.getSystemService(WifiManager::class.java)
        val info = wm.connectionInfo
        val lp = cm.getLinkProperties(net)
        val phoneIp = lp?.linkAddresses?.firstOrNull { it.address is Inet4Address }?.address?.hostAddress
        val gateway = lp?.routes
            ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway?.hostAddress
            ?: phoneIp?.substringBeforeLast('.')?.let { "$it.1" }
        val ssid = info?.ssid?.trim('"')?.takeIf { it.isNotBlank() && it != "<unknown ssid>" }
        return WifiStatus(
            connected = true,
            ssid = ssid,
            frequencyMhz = info?.frequency ?: 0,
            rssiDbm = info?.rssi ?: 0,
            linkMbps = info?.linkSpeed ?: 0,
            phoneIp = phoneIp,
            gateway = gateway,
            hasInternet = cm.getNetworkCapabilities(net)
                ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true,
        )
    }

    /** Time for a TCP handshake in ms, or null if it failed or timed out. */
    fun tcpConnectMs(net: Network?, host: String, port: Int): Double? {
        val socket = net?.socketFactory?.createSocket() ?: java.net.Socket()
        return try {
            val start = System.nanoTime()
            socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            (System.nanoTime() - start) / 1_000_000.0
        } catch (e: IOException) {
            null
        } finally {
            try {
                socket.close()
            } catch (_: IOException) {
            }
        }
    }

    /** Asks Sunshine who it is, the same way Moonlight does. Returns "hostname (version)" or null. */
    fun sunshineInfo(net: Network?, host: String): String? {
        val url = URL("http://$host:47989/serverinfo?uniqueid=0123456789ABCDEF&uuid=${UUID.randomUUID()}")
        val conn = (net?.openConnection(url) ?: url.openConnection()) as HttpURLConnection
        return try {
            conn.connectTimeout = 2000
            conn.readTimeout = 2000
            if (conn.responseCode != 200) return null
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val name = Regex("<hostname>(.*?)</hostname>").find(body)?.groupValues?.get(1)
            val version = Regex("<appversion>(.*?)</appversion>").find(body)?.groupValues?.get(1)
            when {
                name != null && version != null -> "$name (version $version)"
                name != null -> name
                else -> "replied, but no hostname"
            }
        } catch (e: IOException) {
            null
        } finally {
            conn.disconnect()
        }
    }
}
