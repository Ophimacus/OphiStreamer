package com.ophistreamer.tester

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// SteamOS-inspired palette: deep navy, slate text, bright blue accent.
private val BgTop = Color(0xFF1B2838)
private val BgBottom = Color(0xFF0B0F14)
private val CardBg = Color(0xFF151C25)
private val CardBorder = Color(0xFF26313E)
private val Divider = Color(0xFF212B37)
private val TextMain = Color(0xFFDCDEDF)
private val Muted = Color(0xFF8B98A5)
private val Accent = Color(0xFF1A9FFF)
private val AccentDeep = Color(0xFF0B6FD1)
private val Good = Color(0xFF59BF40)
private val Warn = Color(0xFFE6B450)
private val Bad = Color(0xFFE5534B)
private val HeroTop = Color(0xFF2A475E)

private val CardShape = RoundedCornerShape(6.dp)

enum class Level(val color: Color) { PASS(Good), WARN(Warn), FAIL(Bad), INFO(Muted) }

data class Check(val name: String, val level: Level, val detail: String)

/** Live gamepad input, fed by the activity so it works whatever has focus. */
object GamepadInput {
    var lastButton by mutableStateOf("")
    var leftX by mutableFloatStateOf(0f)
    var leftY by mutableFloatStateOf(0f)
    var rightX by mutableFloatStateOf(0f)
    var rightY by mutableFloatStateOf(0f)
    var events by mutableIntStateOf(0)
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Accent, background = BgBottom, surface = CardBg)) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(Brush.verticalGradient(listOf(BgTop, BgBottom))),
                ) {
                    TesterScreen(onKeepScreenOn = ::keepScreenOn)
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_GAMEPAD) && KeyEvent.isGamepadButton(event.keyCode)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                GamepadInput.lastButton = KeyEvent.keyCodeToString(event.keyCode).removePrefix("KEYCODE_")
                GamepadInput.events++
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_JOYSTICK) && event.action == MotionEvent.ACTION_MOVE) {
            GamepadInput.leftX = event.getAxisValue(MotionEvent.AXIS_X)
            GamepadInput.leftY = event.getAxisValue(MotionEvent.AXIS_Y)
            GamepadInput.rightX = event.getAxisValue(MotionEvent.AXIS_Z)
            GamepadInput.rightY = event.getAxisValue(MotionEvent.AXIS_RZ)
            GamepadInput.events++
            return true
        }
        return super.dispatchGenericMotionEvent(event)
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
    var hotspot by remember { mutableStateOf(NetProbe.phoneHotspot(context)) }
    var host by remember { mutableStateOf(if (hotspot != null) "" else wifi.gateway ?: "192.168.137.1") }
    var scanning by remember { mutableStateOf(false) }
    var foundPcs by remember { mutableStateOf(listOf<String>()) }
    var controllers by remember { mutableStateOf(DeviceProbe.controllers()) }
    val screen = remember { DeviceProbe.screen(context) }
    val decoders = remember { DeviceProbe.decoders() }
    val advice = remember { DeviceProbe.advice(screen, decoders) }
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

    fun findPc() = scope.launch {
        val hs = hotspot ?: return@launch
        scanning = true
        try {
            foundPcs = NetProbe.findSunshineHosts(hs)
            foundPcs.firstOrNull()?.let { host = it }
        } finally {
            scanning = false
        }
    }

    fun refresh() {
        wifi = NetProbe.wifiStatus(context)
        hotspot = NetProbe.phoneHotspot(context)
        if (hotspot != null) findPc() else wifi.gateway?.let { host = it }
        controllers = DeviceProbe.controllers()
    }

    LaunchedEffect(Unit) { if (hotspot != null) findPc() }

    fun runTest() = scope.launch {
        running = true
        copied = false
        checks = emptyList()
        samples.clear()
        progress = 0f
        onKeepScreenOn(true)
        val locks = DeviceProbe.acquireStreamingWifiLocks(context)
        try {
            val results = mutableListOf<Check>()

            phase = "Checking Wi-Fi"
            wifi = NetProbe.wifiStatus(context)
            hotspot = NetProbe.phoneHotspot(context)
            controllers = DeviceProbe.controllers()
            val hs = hotspot
            if (hs != null) {
                results += Check("Phone hotspot", Level.PASS, "On (${hs.iface}, ${hs.ip}). Check AP band is 5 GHz.")
                val reachable = host.isNotBlank() &&
                    withContext(Dispatchers.IO) { NetProbe.tcpConnectMs(null, host, 47989) } != null
                if (!reachable) {
                    phase = "Looking for the PC on the hotspot"
                    foundPcs = NetProbe.findSunshineHosts(hs)
                    host = foundPcs.firstOrNull() ?: ""
                }
                results += if (host.isNotBlank()) {
                    Check("PC found", Level.PASS, host)
                } else {
                    Check("PC found", Level.FAIL, "No PC with Apollo on the hotspot. Connect the laptop and start Apollo.")
                }
            } else {
                results += wifiChecks(wifi)
            }
            results += controllerCheck(controllers)
            if (host.isBlank()) {
                checks = results
                return@launch
            }
            // Over our own hotspot there is no client Network object; the kernel routes the subnet directly.
            val net = if (hs != null) null else NetProbe.wifiNetwork(context)

            phase = "Checking Apollo on $host"
            val open = withContext(Dispatchers.IO) {
                NetProbe.SUNSHINE_TCP_PORTS.associateWith { NetProbe.tcpConnectMs(net, host, it) != null }
            }
            results += portCheck(open)
            val info = withContext(Dispatchers.IO) { NetProbe.sunshineInfo(net, host) }
            results += if (info != null) {
                Check("Streaming host found", Level.PASS, info)
            } else {
                Check("Streaming host found", Level.WARN, "No answer from http://$host:47989/serverinfo")
            }
            checks = results.toList()

            val port = NetProbe.SUNSHINE_TCP_PORTS.firstOrNull { open[it] == true }
            if (port == null) {
                results += Check("Latency", Level.FAIL, "Can't measure: no Apollo port is reachable")
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
            DeviceProbe.release(locks)
            running = false
            phase = ""
            onKeepScreenOn(false)
        }
    }

    val apMode = hotspot != null
    val ready = checks.isNotEmpty() && checks.none { it.level == Level.FAIL }
    val status = when {
        running -> "Testing" to Accent
        checks.isEmpty() -> (if (wifi.connected || apMode) "Not tested" else "Offline") to Muted
        ready -> "Ready to stream" to Good
        else -> "Needs attention" to Bad
    }

    Column(
        Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // ---- Top bar
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("OPHISTREAMER", color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 3.sp)
                Text("Link Check", color = TextMain, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            }
            Pill(status.first, status.second)
        }

        // ---- Hero
        Box(
            Modifier
                .fillMaxWidth()
                .border(1.dp, CardBorder, CardShape)
                .background(Brush.verticalGradient(listOf(HeroTop, CardBg)), CardShape)
                .padding(16.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Column {
                    Text(
                        when {
                            apMode -> "Phone hotspot on"
                            wifi.connected -> "Connected to ${wifi.ssid ?: "Wi-Fi"}"
                            else -> "Not connected"
                        },
                        color = TextMain, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                    )
                    Text(
                        when {
                            apMode && scanning -> "Looking for the PC…"
                            apMode && host.isBlank() -> "Connect the laptop to this hotspot"
                            apMode -> "PC at $host"
                            wifi.connected -> "PC at ${wifi.gateway ?: "?"} · ${wifi.frequencyMhz} MHz"
                            else -> "Turn on this phone's hotspot, or join the laptop's"
                        },
                        color = Muted, fontSize = 13.sp,
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (apMode) {
                        StatTile("ON", "HOTSPOT", Good)
                        StatTile(if (host.isBlank()) "-" else "FOUND", "PC", if (host.isBlank()) Muted else Good)
                        StatTile(
                            if (samples.isEmpty()) "-" else "%.1f".format(LatencyStats(samples.toList()).avg),
                            "AVG ms", TextMain,
                        )
                    } else {
                        StatTile(if (wifi.connected) wifi.band else "-", "BAND", bandLevel(wifi).color)
                        StatTile(if (wifi.connected) "${wifi.rssiDbm}" else "-", "SIGNAL dBm", signalLevel(wifi.rssiDbm).color)
                        StatTile(if (wifi.connected) "${wifi.linkMbps}" else "-", "LINK Mbps", linkLevel(wifi.linkMbps).color)
                    }
                }
            }
        }

        // ---- Connection
        SectionHeader("Connection")
        SteamCard {
            val hs = hotspot
            if (hs != null) {
                SettingRow("Mode", "Phone is the hotspot", Accent)
                SettingRow("Phone IP", hs.ip)
                SettingRow(
                    "PC address",
                    when {
                        scanning -> "Searching…"
                        host.isBlank() -> "Not found yet"
                        else -> host
                    },
                    if (host.isBlank()) Warn else TextMain,
                    sub = if (foundPcs.size > 1) "Found: ${foundPcs.joinToString()}" else null,
                )
                SettingRow(
                    "Hotspot band",
                    "Set to 5 GHz",
                    Warn,
                    sub = "Android doesn't let apps read it: Personal hotspot > More > AP band",
                    last = true,
                )
            } else {
                SettingRow("Network", wifi.ssid ?: if (wifi.connected) "Name hidden" else "-")
                SettingRow("Phone IP", wifi.phoneIp ?: "-")
                SettingRow("PC address", wifi.gateway ?: "-")
                SettingRow(
                    "Internet on hotspot",
                    if (wifi.hasInternet) "Yes" else "No",
                    if (wifi.hasInternet) Good else Warn,
                    sub = if (wifi.connected && !wifi.hasInternet) "Android's low-latency Wi-Fi mode needs it" else null,
                    last = true,
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondaryButton("Refresh", enabled = !running && !scanning, modifier = Modifier.weight(1f)) { refresh() }
            SecondaryButton("Hotspot settings", modifier = Modifier.weight(1f)) { openHotspotSettings(context) }
        }
        if (!apMode && !hasLocation) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SecondaryButton("Show Wi-Fi name", modifier = Modifier.weight(1f)) {
                    permissionLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                }
            }
        }

        // ---- Controller
        SectionHeader("Controller")
        SteamCard {
            if (controllers.isEmpty()) {
                SettingRow("No controller found", "", sub = "Plug in the GameSir, turn on OTG, then tap Refresh")
            } else {
                for (c in controllers) {
                    SettingRow(
                        c.name,
                        if (c.external) "Connected" else "Built-in",
                        Good,
                        sub = "ID %04x:%04x · rumble %s".format(c.vendorId, c.productId, if (c.vibrates) "yes" else "no"),
                    )
                }
            }
            SettingRow(
                "Live input",
                GamepadInput.lastButton.ifBlank { "Press a button" },
                if (GamepadInput.events > 0) Accent else Muted,
                sub = "L %+.2f %+.2f   R %+.2f %+.2f".format(
                    GamepadInput.leftX, GamepadInput.leftY, GamepadInput.rightX, GamepadInput.rightY,
                ),
                last = true,
            )
        }

        // ---- Phone
        SectionHeader("This phone")
        SteamCard {
            SettingRow("Screen", "${screen.widthPx}×${screen.heightPx} · ${screen.maxRefreshHz} Hz")
            decoders.forEachIndexed { i, d ->
                SettingRow(
                    d.label,
                    if (d.codecName == null) "Not supported"
                    else "720p ${fpsText(d.maxFps720)} · 1080p ${fpsText(d.maxFps1080)}",
                    when {
                        d.codecName == null -> Muted
                        d.hardware -> Good
                        else -> Warn
                    },
                    sub = d.codecName?.let { if (d.hardware) "Hardware decoder" else "Software only, avoid" },
                    last = i == decoders.lastIndex,
                )
            }
        }

        // ---- Moonlight advice
        SectionHeader("Artemis settings for this phone")
        SteamCard {
            SettingRow("Resolution", advice.resolution)
            SettingRow("Frame rate", "${advice.fps} fps")
            SettingRow("Video codec", advice.codec)
            SettingRow("Bitrate", "${advice.bitrateMbps} Mbps")
            SettingRow("Frame pacing", "Prefer lowest latency")
            SettingRow("Performance overlay", "On")
            SettingRow(
                "Next step",
                "",
                sub = advice.tryLater ?: "Raise bitrate in small steps while the overlay shows no drops",
                last = true,
            )
        }

        // ---- Test controls
        SectionHeader("Link test")
        OutlinedTextField(
            value = host,
            onValueChange = { host = it.trim() },
            label = { Text("PC address") },
            singleLine = true,
            enabled = !running,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            shape = CardShape,
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Accent,
                unfocusedBorderColor = CardBorder,
                focusedLabelColor = Accent,
                unfocusedLabelColor = Muted,
                focusedTextColor = TextMain,
                unfocusedTextColor = TextMain,
                cursorColor = Accent,
                focusedContainerColor = CardBg,
                unfocusedContainerColor = CardBg,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
        Segmented(
            options = listOf(30, 60, 120),
            selected = durationSec,
            label = { "${it}s" },
            enabled = !running,
        ) { durationSec = it }

        PrimaryButton(
            text = if (running) "Testing…" else "Run link test",
            enabled = !running && !scanning && (host.isNotBlank() || apMode),
        ) { runTest() }

        if (running) {
            LinearProgressIndicator(
                progress = { progress },
                color = Accent,
                trackColor = CardBorder,
                modifier = Modifier.fillMaxWidth().height(4.dp),
            )
            Text(phase, color = Muted, fontSize = 12.sp)
        }

        // ---- Latency
        if (samples.isNotEmpty()) {
            val stats = LatencyStats(samples.toList())
            SectionHeader("Latency to PC")
            SteamCard {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    LatencyChart(
                        samples = samples,
                        expected = (durationSec * 1000 / NetProbe.SAMPLE_INTERVAL_MS).toInt(),
                        modifier = Modifier.fillMaxWidth().height(110.dp),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        StatTile("%.1f".format(stats.avg), "AVG ms", TextMain)
                        StatTile("%.1f".format(stats.p99), "P99 ms", TextMain)
                        StatTile("${stats.spikes}", "SPIKES", if (stats.spikes == 0) Good else Warn)
                        StatTile("${stats.lost}", "LOST", if (stats.lost == 0) Good else Bad)
                    }
                }
            }
        }

        // ---- Results
        if (checks.isNotEmpty()) {
            SectionHeader("Results")
            SteamCard {
                checks.forEachIndexed { i, c ->
                    ResultRow(c, last = i == checks.lastIndex)
                }
            }
            if (!running) {
                SecondaryButton(if (copied) "Copied - paste it to Claude" else "Copy report") {
                    val stats = if (samples.isEmpty()) null else LatencyStats(samples.toList())
                    clipboard.setText(
                        AnnotatedString(
                            buildReport(context, wifi, hotspot, host, checks, stats, screen, decoders, advice, controllers),
                        ),
                    )
                    copied = true
                }
            }
        }

        Text(
            "Holds the same Wi-Fi locks as Artemis/Moonlight during the test.",
            color = Muted.copy(alpha = 0.6f), fontSize = 11.sp,
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            textAlign = TextAlign.Center,
        )
    }
}

// ---------------------------------------------------------------- components

@Composable
private fun SectionHeader(text: String) {
    Text(
        text.uppercase(),
        color = Muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.6.sp,
        modifier = Modifier.padding(top = 10.dp, start = 4.dp),
    )
}

@Composable
private fun SteamCard(content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .border(1.dp, CardBorder, CardShape)
            .background(CardBg, CardShape),
    ) { content() }
}

@Composable
private fun SettingRow(
    label: String,
    value: String,
    valueColor: Color = TextMain,
    sub: String? = null,
    last: Boolean = false,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, color = TextMain, fontSize = 15.sp)
            if (sub != null) Text(sub, color = Muted, fontSize = 12.sp)
        }
        if (value.isNotEmpty()) {
            Text(value, color = valueColor, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End)
        }
    }
    if (!last) HorizontalDivider(color = Divider, thickness = 1.dp, modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun ResultRow(c: Check, last: Boolean) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(c.name, color = TextMain, fontSize = 15.sp)
            if (c.detail.isNotBlank()) Text(c.detail, color = Muted, fontSize = 12.sp)
        }
        Pill(c.level.name, c.level.color)
    }
    if (!last) HorizontalDivider(color = Divider, thickness = 1.dp, modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun Pill(text: String, color: Color) {
    Row(
        Modifier
            .background(color.copy(alpha = 0.16f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(7.dp).background(color, CircleShape))
        Text(text.uppercase(), color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
    }
}

@Composable
private fun RowScope.StatTile(value: String, label: String, color: Color) {
    Column(
        Modifier
            .weight(1f)
            .background(Color.Black.copy(alpha = 0.25f), CardShape)
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, color = color, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text(label, color = Muted, fontSize = 10.sp, letterSpacing = 1.sp)
    }
}

@Composable
private fun PrimaryButton(text: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(56.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .background(Brush.horizontalGradient(listOf(Accent, AccentDeep)), RoundedCornerShape(4.dp))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text.uppercase(), color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp)
    }
}

@Composable
private fun SecondaryButton(
    text: String,
    enabled: Boolean = true,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onClick: () -> Unit,
) {
    Box(
        modifier
            .height(46.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .border(1.dp, CardBorder, RoundedCornerShape(4.dp))
            .background(Color(0xFF1F2833), RoundedCornerShape(4.dp))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = TextMain, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun <T> Segmented(
    options: List<T>,
    selected: T,
    label: (T) -> String,
    enabled: Boolean,
    onSelect: (T) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .border(1.dp, CardBorder, CardShape)
            .background(CardBg, CardShape)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (o in options) {
            val isSel = o == selected
            Box(
                Modifier
                    .weight(1f)
                    .height(38.dp)
                    .background(if (isSel) Accent else Color.Transparent, RoundedCornerShape(4.dp))
                    .clickable(enabled = enabled) { onSelect(o) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label(o),
                    color = if (isSel) Color.White else Muted,
                    fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun LatencyChart(samples: List<Double?>, expected: Int, modifier: Modifier) {
    Canvas(modifier) {
        val maxMs = 100.0
        val step = size.width / maxOf(samples.size, expected, 1)
        val barWidth = step.coerceAtLeast(1f)
        val spikeY = size.height * (1 - (LatencyStats.SPIKE_MS / maxMs)).toFloat()
        drawLine(Warn.copy(alpha = 0.35f), Offset(0f, spikeY), Offset(size.width, spikeY), 2f)
        samples.forEachIndexed { i, v ->
            val x = i * step + barWidth / 2
            if (v == null) {
                drawLine(Bad, Offset(x, 0f), Offset(x, size.height), barWidth)
            } else {
                val h = (v.coerceAtMost(maxMs) / maxMs * size.height).toFloat().coerceAtLeast(2f)
                val color = if (v >= LatencyStats.SPIKE_MS) Warn else Accent
                drawLine(color, Offset(x, size.height), Offset(x, size.height - h), barWidth)
            }
        }
    }
}

// ---------------------------------------------------------------- checks

/** Opens the hotspot screen; the tether action is not public on every build, so fall back to wireless settings. */
private fun openHotspotSettings(context: Context) {
    for (action in listOf("android.settings.TETHER_SETTINGS", Settings.ACTION_WIRELESS_SETTINGS)) {
        try {
            context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (_: ActivityNotFoundException) {
        }
    }
}

private fun fpsText(fps: Int) = if (fps == 0) "no" else "$fps fps"

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
        Check(
            "Internet on hotspot",
            if (w.hasInternet) Level.PASS else Level.WARN,
            if (w.hasInternet) "Android can use its low-latency Wi-Fi mode"
            else "Without it Android won't enable low-latency Wi-Fi mode. Keep the laptop sharing its internet.",
        ),
    )
}

private fun controllerCheck(list: List<ControllerInfo>): Check =
    if (list.isEmpty()) {
        Check("Controller", Level.WARN, "None found. Plug in the GameSir and turn on OTG.")
    } else {
        Check("Controller", Level.PASS, list.joinToString { it.name })
    }

private fun portCheck(open: Map<Int, Boolean>): Check {
    val list = open.entries.joinToString { "${it.key} ${if (it.value) "open" else "closed"}" }
    return when {
        open.values.all { it } -> Check("Host ports", Level.PASS, list)
        open.values.any { it } -> Check("Host ports", Level.WARN, list)
        else -> Check(
            "Host ports", Level.FAIL,
            "$list. Is Apollo running? Run the Test Kit on the PC (it sets up the firewall).",
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

@Suppress("DEPRECATION")
private fun buildReport(
    context: Context,
    w: WifiStatus,
    hotspot: HotspotInfo?,
    host: String,
    checks: List<Check>,
    stats: LatencyStats?,
    screen: ScreenInfo,
    decoders: List<DecoderInfo>,
    advice: MoonlightAdvice,
    controllers: List<ControllerInfo>,
): String {
    val version = context.packageManager.getPackageInfo(context.packageName, 0).versionName
    return buildString {
        appendLine("OphiStreamer Link Check report")
        appendLine("Date: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())}")
        appendLine("Phone: ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}, app $version")
        appendLine("Screen: ${screen.widthPx}x${screen.heightPx} @ ${screen.maxRefreshHz} Hz")
        for (d in decoders) {
            appendLine(
                "Decoder ${d.label}: ${d.codecName ?: "none"} (${if (d.hardware) "hw" else "sw"}), " +
                    "720p ${d.maxFps720} fps, 1080p ${d.maxFps1080} fps",
            )
        }
        if (hotspot != null) {
            appendLine("Mode: phone is the hotspot (${hotspot.iface}, ${hotspot.ip}) | PC: ${host.ifBlank { "not found" }}")
        } else {
            appendLine("Mode: phone on Wi-Fi")
            appendLine("Wi-Fi: ${w.ssid ?: "?"} | ${w.band} ${w.frequencyMhz} MHz | ${w.rssiDbm} dBm | ${w.linkMbps} Mbps | internet ${w.hasInternet}")
            appendLine("Phone IP: ${w.phoneIp ?: "?"} | PC: $host")
        }
        for (c in controllers) {
            appendLine("Controller: ${c.name} (%04x:%04x, external ${c.external}, rumble ${c.vibrates})".format(c.vendorId, c.productId))
        }
        if (controllers.isEmpty()) appendLine("Controller: none")
        appendLine("Advice: ${advice.resolution} @ ${advice.fps} fps, ${advice.codec}, ${advice.bitrateMbps} Mbps; ${advice.tryLater ?: "-"}")
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
