package com.ophistreamer.tester

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val Bg = Color(0xFF0E1116)
private val PanelBg = Color(0xFF181C23)
private val Muted = Color(0xFF8B949E)
private val Green = Color(0xFF3DDC84)
private val Amber = Color(0xFFFFC107)
private val Red = Color(0xFFFF5252)

enum class Level(val color: Color) { PASS(Green), WARN(Amber), FAIL(Red), INFO(Muted) }

data class Check(val name: String, val level: Level, val detail: String)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Green, background = Bg, surface = PanelBg)) {
                Surface(Modifier.fillMaxSize(), color = Bg) {
                    TesterScreen(onKeepScreenOn = ::keepScreenOn)
                }
            }
        }
    }

    private fun keepScreenOn(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}

@Composable
fun TesterScreen(onKeepScreenOn: (Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    var wifi by remember { mutableStateOf(NetProbe.wifiStatus(context)) }
    var host by remember { mutableStateOf(wifi.gateway ?: "192.168.137.1") }
    var durationSec by remember { mutableIntStateOf(60) }
    var running by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0f) }
    var phase by remember { mutableStateOf("") }
    val samples = remember { mutableStateListOf<Double?>() }
    var checks by remember { mutableStateOf(listOf<Check>()) }
    var copied by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        wifi = NetProbe.wifiStatus(context)
    }
    val hasLocation = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED

    fun runTest() = scope.launch {
        running = true
        copied = false
        checks = emptyList()
        samples.clear()
        progress = 0f
        onKeepScreenOn(true)
        try {
            val results = mutableListOf<Check>()

            phase = "Checking Wi-Fi"
            wifi = NetProbe.wifiStatus(context)
            results += wifiChecks(wifi)
            val net = NetProbe.wifiNetwork(context)

            phase = "Checking Sunshine ports on $host"
            val open = withContext(Dispatchers.IO) {
                NetProbe.SUNSHINE_TCP_PORTS.associateWith { NetProbe.tcpConnectMs(net, host, it) != null }
            }
            results += portCheck(open)
            val info = withContext(Dispatchers.IO) { NetProbe.sunshineInfo(net, host) }
            results += if (info != null) {
                Check("Sunshine found", Level.PASS, info)
            } else {
                Check("Sunshine found", Level.WARN, "No answer from http://$host:47989/serverinfo")
            }
            checks = results.toList()

            val port = NetProbe.SUNSHINE_TCP_PORTS.firstOrNull { open[it] == true }
            if (port == null) {
                results += Check("Latency", Level.FAIL, "Can't measure: no Sunshine port is reachable")
            } else {
                phase = "Measuring latency to $host:$port"
                val totalMs = durationSec * 1000L
                val start = SystemClock.elapsedRealtime()
                while (SystemClock.elapsedRealtime() - start < totalMs) {
                    samples += withContext(Dispatchers.IO) { NetProbe.tcpConnectMs(net, host, port) }
                    progress = ((SystemClock.elapsedRealtime() - start).toFloat() / totalMs).coerceAtMost(1f)
                    delay(NetProbe.SAMPLE_INTERVAL_MS)
                }
                results += latencyCheck(LatencyStats(samples.toList()))
            }
            checks = results
        } finally {
            running = false
            phase = ""
            onKeepScreenOn(false)
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("OphiStreamer Tester", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(
            "Stands in for the Steam Deck. Join the laptop's hotspot, make sure Sunshine is running, then run the test.",
            style = MaterialTheme.typography.bodySmall,
            color = Muted,
        )

        Panel {
            Text("Wi-Fi", fontWeight = FontWeight.SemiBold)
            if (!wifi.connected) {
                Text("Not connected to Wi-Fi", color = Red)
            } else {
                InfoRow("Network", wifi.ssid ?: "hidden (tap Show name)")
                InfoRow("Band", "${wifi.band} (${wifi.frequencyMhz} MHz)", bandLevel(wifi).color)
                InfoRow("Signal", "${wifi.rssiDbm} dBm", signalLevel(wifi.rssiDbm).color)
                InfoRow("Link speed", "${wifi.linkMbps} Mbps", linkLevel(wifi.linkMbps).color)
                InfoRow("Phone IP", wifi.phoneIp ?: "-")
                InfoRow("PC address", wifi.gateway ?: "-")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = {
                    wifi = NetProbe.wifiStatus(context)
                    wifi.gateway?.let { host = it }
                }, enabled = !running) { Text("Refresh") }
                if (!hasLocation) {
                    OutlinedButton(onClick = {
                        permissionLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                    }) { Text("Show name") }
                }
            }
        }

        OutlinedTextField(
            value = host,
            onValueChange = { host = it.trim() },
            label = { Text("PC address (Sunshine)") },
            singleLine = true,
            enabled = !running,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth(),
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Latency test", color = Muted)
            for (s in listOf(30, 60, 120)) {
                FilterChip(
                    selected = durationSec == s,
                    onClick = { durationSec = s },
                    label = { Text("${s}s") },
                    enabled = !running,
                )
            }
        }

        Button(onClick = { runTest() }, enabled = !running && host.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
            Text(if (running) "Testing..." else "Run full test")
        }

        if (running) {
            LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
            Text(phase, style = MaterialTheme.typography.bodySmall, color = Muted)
        }

        if (samples.isNotEmpty()) {
            val stats = LatencyStats(samples.toList())
            Panel {
                Text("Latency to PC", fontWeight = FontWeight.SemiBold)
                LatencyChart(
                    samples = samples,
                    expected = (durationSec * 1000 / NetProbe.SAMPLE_INTERVAL_MS).toInt(),
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                )
                Text(
                    "avg %.1f ms · p99 %.1f ms · max %.1f ms · spikes ≥50 ms: %d · lost %d/%d".format(
                        stats.avg, stats.p99, stats.max, stats.spikes, stats.lost, stats.sent,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted,
                )
            }
        }

        if (checks.isNotEmpty()) {
            Panel {
                Text("Results", fontWeight = FontWeight.SemiBold)
                for (c in checks) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(c.level.name, color = c.level.color, fontFamily = FontFamily.Monospace, modifier = Modifier.width(44.dp))
                        Column {
                            Text(c.name)
                            if (c.detail.isNotBlank()) Text(c.detail, style = MaterialTheme.typography.bodySmall, color = Muted)
                        }
                    }
                }
            }
            if (!running) {
                OutlinedButton(onClick = {
                    val stats = if (samples.isEmpty()) null else LatencyStats(samples.toList())
                    clipboard.setText(AnnotatedString(buildReport(context, wifi, host, checks, stats)))
                    copied = true
                }, modifier = Modifier.fillMaxWidth()) {
                    Text(if (copied) "Copied - paste it to Claude" else "Copy report")
                }
            }
        }
    }
}

@Composable
private fun Panel(content: @Composable () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = PanelBg), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
    }
}

@Composable
private fun InfoRow(label: String, value: String, valueColor: Color = Color.Unspecified) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = Muted)
        Text(value, color = valueColor)
    }
}

@Composable
private fun LatencyChart(samples: List<Double?>, expected: Int, modifier: Modifier) {
    Canvas(modifier) {
        val maxMs = 100.0
        val step = size.width / maxOf(samples.size, expected, 1)
        val barWidth = step.coerceAtLeast(1f)
        val spikeY = size.height * (1 - (LatencyStats.SPIKE_MS / maxMs)).toFloat()
        drawLine(Amber.copy(alpha = 0.4f), Offset(0f, spikeY), Offset(size.width, spikeY), 2f)
        samples.forEachIndexed { i, v ->
            val x = i * step + barWidth / 2
            if (v == null) {
                drawLine(Red, Offset(x, 0f), Offset(x, size.height), barWidth)
            } else {
                val h = (v.coerceAtMost(maxMs) / maxMs * size.height).toFloat().coerceAtLeast(2f)
                val color = if (v >= LatencyStats.SPIKE_MS) Amber else Green
                drawLine(color, Offset(x, size.height), Offset(x, size.height - h), barWidth)
            }
        }
    }
}

private fun bandLevel(w: WifiStatus) = when (w.band) {
    "5 GHz", "6 GHz" -> Level.PASS
    "2.4 GHz" -> Level.WARN
    else -> Level.INFO
}

private fun signalLevel(rssi: Int) = when {
    rssi >= -60 -> Level.PASS
    rssi >= -70 -> Level.WARN
    else -> Level.FAIL
}

private fun linkLevel(mbps: Int) = when {
    mbps >= 200 -> Level.PASS
    mbps >= 72 -> Level.WARN
    else -> Level.FAIL
}

private fun wifiChecks(w: WifiStatus): List<Check> {
    if (!w.connected) return listOf(Check("On Wi-Fi", Level.FAIL, "Connect the phone to the laptop's hotspot"))
    return listOf(
        Check("On Wi-Fi", Level.PASS, w.ssid ?: "network name hidden"),
        Check(
            "Band 5 GHz", bandLevel(w),
            when (bandLevel(w)) {
                Level.PASS -> "${w.band}, ${w.frequencyMhz} MHz"
                Level.WARN -> "Hotspot is on 2.4 GHz. On Intel cards, connect the laptop to 5 GHz Wi-Fi first."
                else -> "Unknown frequency"
            },
        ),
        Check("Signal", signalLevel(w.rssiDbm), "${w.rssiDbm} dBm (good is -60 or higher)"),
        Check("Link speed", linkLevel(w.linkMbps), "${w.linkMbps} Mbps (good is 200 or more)"),
    )
}

private fun portCheck(open: Map<Int, Boolean>): Check {
    val list = open.entries.joinToString { "${it.key} ${if (it.value) "open" else "closed"}" }
    return when {
        open.values.all { it } -> Check("Sunshine ports", Level.PASS, list)
        open.values.any { it } -> Check("Sunshine ports", Level.WARN, list)
        else -> Check(
            "Sunshine ports", Level.FAIL,
            "$list. Is Sunshine running? Run Firewall-Setup.cmd on the PC.",
        )
    }
}

private fun latencyCheck(s: LatencyStats): Check {
    val detail = "avg %.1f ms, p99 %.1f ms, max %.1f ms, spikes %d, lost %d/%d".format(
        s.avg, s.p99, s.max, s.spikes, s.lost, s.sent,
    )
    val lossPct = if (s.sent == 0) 100.0 else s.lost * 100.0 / s.sent
    val level = when {
        s.spikes == 0 && s.lost == 0 && s.p99 < 20 -> Level.PASS
        s.spikes <= 2 && lossPct <= 1.0 -> Level.WARN
        else -> Level.FAIL
    }
    return Check("Latency", level, detail)
}

private fun buildReport(context: Context, w: WifiStatus, host: String, checks: List<Check>, stats: LatencyStats?): String {
    val version = context.packageManager.getPackageInfo(context.packageName, 0).versionName
    return buildString {
        appendLine("OphiStreamer Tester report")
        appendLine("Date: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())}")
        appendLine("Phone: ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}, app $version")
        appendLine("Wi-Fi: ${w.ssid ?: "?"} | ${w.band} ${w.frequencyMhz} MHz | ${w.rssiDbm} dBm | ${w.linkMbps} Mbps")
        appendLine("Phone IP: ${w.phoneIp ?: "?"} | PC: $host")
        if (stats != null) {
            appendLine(
                "Latency: avg %.1f ms, p99 %.1f ms, max %.1f ms, spikes>=50ms %d, lost %d/%d".format(
                    stats.avg, stats.p99, stats.max, stats.spikes, stats.lost, stats.sent,
                ),
            )
        }
        appendLine()
        for (c in checks) appendLine("[${c.level}] ${c.name} - ${c.detail}")
    }
}
