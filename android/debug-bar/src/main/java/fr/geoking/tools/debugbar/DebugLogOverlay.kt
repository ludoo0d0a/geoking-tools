package fr.geoking.tools.debugbar

import fr.geoking.tools.debugbar.model.HostDataConsumption
import fr.geoking.tools.debugbar.model.NetworkLog
import fr.geoking.tools.debugbar.model.ProviderTraceEntry
import fr.geoking.tools.debugbar.model.ProviderTracePhase
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kotlinx.serialization.json.*
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun DebugLogOverlay(
    logs: List<NetworkLog>,
    providerTraces: List<ProviderTraceEntry>,
    hostConsumption: Map<String, HostDataConsumption>,
    totalBytesSent: Long,
    totalBytesReceived: Long,
    disableCache: Boolean,
    onDisableCacheChange: (Boolean) -> Unit,
    onClearCaches: () -> Unit,
    onClearLogs: () -> Unit,
    onResetDataConsumption: () -> Unit,
    modifier: Modifier = Modifier,
    detectedCountries: String? = null,
) {
    var isExpanded by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        DebugLogOverlayContent(
            isExpanded = isExpanded,
            onExpandedChange = { isExpanded = it },
            logs = logs,
            providerTraces = providerTraces,
            hostConsumption = hostConsumption,
            totalBytesSent = totalBytesSent,
            totalBytesReceived = totalBytesReceived,
            disableCache = disableCache,
            onDisableCacheChange = onDisableCacheChange,
            onClearCaches = onClearCaches,
            onClearLogs = onClearLogs,
            onResetDataConsumption = onResetDataConsumption,
            detectedCountries = detectedCountries,
            modifier = Modifier.padding(16.dp)
        )

        if (isExpanded) {
            Popup(
                onDismissRequest = { isExpanded = false },
                properties = PopupProperties(focusable = true)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.4f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = { isExpanded = false }
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    DebugLogOverlayContent(
                        isExpanded = true,
                        onExpandedChange = { isExpanded = it },
                        logs = logs,
                        providerTraces = providerTraces,
                        hostConsumption = hostConsumption,
                        totalBytesSent = totalBytesSent,
                        totalBytesReceived = totalBytesReceived,
                        disableCache = disableCache,
                        onDisableCacheChange = onDisableCacheChange,
                        onClearCaches = onClearCaches,
                        onClearLogs = onClearLogs,
                        onResetDataConsumption = onResetDataConsumption,
                        detectedCountries = detectedCountries,
                        modifier = Modifier
                            .padding(16.dp)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                onClick = { /* Consume clicks to prevent dismissal */ }
                            )
                    )
                }
            }
        }
    }
}

private enum class DebugOverlayTab {
    Network,
    Providers,
    DataConsumption,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DebugLogOverlayContent(
    isExpanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    logs: List<NetworkLog>,
    providerTraces: List<ProviderTraceEntry>,
    hostConsumption: Map<String, HostDataConsumption>,
    totalBytesSent: Long,
    totalBytesReceived: Long,
    disableCache: Boolean,
    onDisableCacheChange: (Boolean) -> Unit,
    onClearCaches: () -> Unit,
    onClearLogs: () -> Unit,
    onResetDataConsumption: () -> Unit,
    detectedCountries: String?,
    modifier: Modifier = Modifier,
) {
    var selectedTab by remember { mutableStateOf(DebugOverlayTab.Network) }
    var selectedLog by remember { mutableStateOf<NetworkLog?>(null) }
    var selectedTrace by remember { mutableStateOf<ProviderTraceEntry?>(null) }
    var selectedHost by remember { mutableStateOf<String?>(null) }
    val availableHosts = remember(logs) {
        logs.map { it.host }.filter { it.isNotEmpty() }.distinct().sorted()
    }
    val hostConsumptionMap = hostConsumption

    Box(modifier = modifier.zIndex(2f)) {
        if (!isExpanded) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                FloatingActionButton(
                    onClick = { onExpandedChange(true) },
                    containerColor = Color(0xFF334155).copy(alpha = 0.8f),
                    contentColor = Color.White,
                    modifier = Modifier.size(48.dp)
                ) {
                    Icon(Icons.Default.BugReport, contentDescription = "Show logs")
                }
            }
        } else {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.9f)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = { /* Consume click to prevent closing when tapping inside */ }
                    ),
                color = Color(0xFF0F172A).copy(alpha = 0.95f),
                shape = RoundedCornerShape(16.dp),
                border = BoxShadow(Color.White.copy(alpha = 0.2f))
            ) {
                Column {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TooltipBox(
                            positionProvider = TooltipDefaults.rememberTooltipPositionProvider(
                                TooltipAnchorPosition.Above,
                            ),
                            tooltip = { PlainTooltip { Text("Disable cache") } },
                            state = rememberTooltipState()
                        ) {
                            IconButton(onClick = { onDisableCacheChange(!disableCache) }) {
                                Icon(
                                    imageVector = if (disableCache) Icons.Default.CloudOff else Icons.Default.Cloud,
                                    contentDescription = "Disable cache",
                                    tint = if (disableCache) Color(0xFFF87171) else MaterialTheme.colorScheme.onSurface
                                )
                            }
                        }
                        TooltipBox(
                            positionProvider = TooltipDefaults.rememberTooltipPositionProvider(
                                TooltipAnchorPosition.Above,
                            ),
                            tooltip = { PlainTooltip { Text("Clear cache") } },
                            state = rememberTooltipState()
                        ) {
                            IconButton(onClick = onClearCaches) {
                                Icon(Icons.Default.Refresh, "Clear cache", tint = MaterialTheme.colorScheme.onSurface)
                            }
                        }
                        TooltipBox(
                            positionProvider = TooltipDefaults.rememberTooltipPositionProvider(
                                TooltipAnchorPosition.Above,
                            ),
                            tooltip = { PlainTooltip { Text("Clear logs") } },
                            state = rememberTooltipState()
                        ) {
                            IconButton(onClick = onClearLogs) {
                                Icon(Icons.Default.DeleteSweep, "Clear logs", tint = MaterialTheme.colorScheme.onSurface)
                            }
                        }
                        TooltipBox(
                            positionProvider = TooltipDefaults.rememberTooltipPositionProvider(
                                TooltipAnchorPosition.Above,
                            ),
                            tooltip = { PlainTooltip { Text("Close") } },
                            state = rememberTooltipState()
                        ) {
                            IconButton(onClick = { onExpandedChange(false) }) {
                                Icon(Icons.Default.Close, "Close", tint = MaterialTheme.colorScheme.onSurface)
                            }
                        }
                    }

                    SecondaryTabRow(
                        selectedTabIndex = selectedTab.ordinal,
                        containerColor = Color.Transparent,
                        contentColor = Color.White,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    ) {
                        Tab(
                            selected = selectedTab == DebugOverlayTab.Network,
                            onClick = { selectedTab = DebugOverlayTab.Network },
                            text = { Text("Network", fontSize = 12.sp) },
                        )
                        Tab(
                            selected = selectedTab == DebugOverlayTab.Providers,
                            onClick = { selectedTab = DebugOverlayTab.Providers },
                            text = { Text("Providers", fontSize = 12.sp) },
                        )
                        Tab(
                            selected = selectedTab == DebugOverlayTab.DataConsumption,
                            onClick = { selectedTab = DebugOverlayTab.DataConsumption },
                            text = { Text("Data Usage", fontSize = 12.sp) },
                        )
                    }

                    Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                        when (selectedTab) {
                            DebugOverlayTab.Network -> NetworkDebugTab(
                                logs = logs,
                                availableHosts = availableHosts,
                                selectedHost = selectedHost,
                                detectedCountries = detectedCountries,
                                onHostSelected = { selectedHost = it },
                                onLogClick = { selectedLog = it },
                            )
                            DebugOverlayTab.Providers -> ProviderTraceTab(
                                traces = providerTraces,
                                onTraceClick = { selectedTrace = it },
                            )
                            DebugOverlayTab.DataConsumption -> DataConsumptionTab(
                                hostConsumptions = remember(hostConsumptionMap) {
                                    hostConsumptionMap.values.sortedByDescending { it.totalBytes }
                                },
                                totalSent = totalBytesSent,
                                totalReceived = totalBytesReceived,
                                onResetClick = onResetDataConsumption
                            )
                        }
                    }
                }
            }
        }
    }

    if (selectedLog != null) {
        LogDetailsDialog(log = selectedLog!!, onDismiss = { selectedLog = null })
    }
    if (selectedTrace != null) {
        ProviderTraceDetailsDialog(trace = selectedTrace!!, onDismiss = { selectedTrace = null })
    }
}

private fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"
    val exp = (Math.log(bytes.toDouble()) / Math.log(1024.0)).toInt()
    val pre = "KMGTPE"[exp - 1]
    return String.format("%.1f %sB", bytes / Math.pow(1024.0, exp.toDouble()), pre)
}

/** Compact size for list rows: `12B`, `1.2KB`, `3.4MB`. */
private fun formatBytesCompact(bytes: Long): String {
    if (bytes < 1024) return "${bytes}B"
    val exp = (Math.log(bytes.toDouble()) / Math.log(1024.0)).toInt().coerceAtMost(5)
    val pre = "KMGTPE"[exp - 1]
    val value = bytes / Math.pow(1024.0, exp.toDouble())
    return if (value >= 10) {
        String.format("%.0f%sB", value, pre)
    } else {
        String.format("%.1f%sB", value, pre)
    }
}

private fun formatTransferSizes(requestBytes: Long, responseBytes: Long): String {
    val parts = mutableListOf<String>()
    if (requestBytes > 0) parts += "↑${formatBytesCompact(requestBytes)}"
    if (responseBytes > 0) parts += "↓${formatBytesCompact(responseBytes)}"
    return parts.joinToString(" ")
}

/** Cap body text before Compose/JSON parsing to avoid OOM on huge payloads (any format). */
private const val MAX_DISPLAY_BODY_CHARS = 64 * 1024
/** Cap line count for CSV / plain-text bodies (virtualized in LazyColumn). */
private const val MAX_DISPLAY_BODY_LINES = 2_000

private data class DisplayBody(
    val text: String,
    val originalLength: Int,
    val truncated: Boolean,
)

private fun truncateForDisplay(body: String, maxChars: Int = MAX_DISPLAY_BODY_CHARS): DisplayBody {
    if (body.length <= maxChars) {
        return DisplayBody(text = body, originalLength = body.length, truncated = false)
    }
    val note = "\n…[truncated for display: showing ${formatBytesCompact(maxChars.toLong())} of ${formatBytesCompact(body.length.toLong())}]"
    return DisplayBody(
        text = body.take(maxChars) + note,
        originalLength = body.length,
        truncated = true,
    )
}

/** Split any text body (CSV, XML, plain, …) into lines, capped to avoid Compose OOM. */
private fun bodyLinesForDisplay(text: String, maxLines: Int = MAX_DISPLAY_BODY_LINES): List<String> {
    val lines = ArrayList<String>(minOf(maxLines + 1, 256))
    var count = 0
    text.lineSequence().forEach { line ->
        if (count >= maxLines) {
            lines.add("…[truncated: more lines not shown]")
            return lines
        }
        lines.add(line)
        count++
    }
    return lines
}

@Composable
private fun NetworkDebugTab(
    logs: List<NetworkLog>,
    availableHosts: List<String>,
    selectedHost: String?,
    detectedCountries: String?,
    onHostSelected: (String?) -> Unit,
    onLogClick: (NetworkLog) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        detectedCountries?.let {
            Text(
                it,
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 10.sp,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
            )
        }

        if (availableHosts.isNotEmpty()) {
            LazyRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    HostFilterChip(
                        label = "All",
                        selected = selectedHost == null,
                        onClick = { onHostSelected(null) },
                    )
                }
                items(availableHosts) { host ->
                    HostFilterChip(
                        label = host,
                        selected = selectedHost == host,
                        onClick = { onHostSelected(if (selectedHost == host) null else host) },
                    )
                }
            }
        }

        val filteredLogs = if (selectedHost == null) logs else logs.filter { it.host == selectedHost }

        LazyColumn(modifier = Modifier.weight(1f)) {
            items(filteredLogs, key = { it.id }) { log ->
                LogItem(log, onClick = { onLogClick(log) })
            }
        }
    }
}

@Composable
private fun HostFilterChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, fontSize = 11.sp) },
        colors = FilterChipDefaults.filterChipColors(
            containerColor = Color.Transparent,
            labelColor = Color.White.copy(alpha = 0.6f),
            selectedContainerColor = Color.White.copy(alpha = 0.2f),
            selectedLabelColor = Color.White
        ),
        border = FilterChipDefaults.filterChipBorder(
            borderColor = Color.White.copy(alpha = 0.2f),
            selectedBorderColor = Color.White.copy(alpha = 0.5f),
            borderWidth = 1.dp,
            selectedBorderWidth = 1.dp,
            enabled = true,
            selected = selected
        )
    )
}

@Composable
private fun ProviderTraceTab(
    traces: List<ProviderTraceEntry>,
    onTraceClick: (ProviderTraceEntry) -> Unit,
) {
    if (traces.isEmpty()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "No provider traces yet",
                color = Color.White.copy(alpha = 0.5f),
                fontSize = 12.sp,
            )
        }
    } else {
        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(traces, key = { it.id }) { trace ->
                ProviderTraceItem(trace, onClick = { onTraceClick(trace) })
            }
        }
    }
}

@Composable
private fun ProviderTraceItem(trace: ProviderTraceEntry, onClick: () -> Unit) {
    val time = remember(trace.timestamp) {
        SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault()).format(Date(trace.timestamp))
    }
    val phaseColor = providerPhaseColor(trace.phase)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = trace.phase.name,
                color = phaseColor,
                fontWeight = FontWeight.Bold,
                fontSize = 10.sp,
                modifier = Modifier
                    .background(phaseColor.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp, vertical = 2.dp)
            )
            trace.provider?.let { provider ->
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = provider,
                    color = Color(0xFF93C5FD),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            trace.poiCount?.let { count ->
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "$count POIs",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 10.sp,
                )
            }
            trace.durationMs?.let { ms ->
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "${ms}ms",
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 10.sp,
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = time,
                color = Color.White.copy(alpha = 0.4f),
                fontSize = 10.sp,
            )
        }
        Text(
            text = trace.message,
            color = Color.White.copy(alpha = 0.85f),
            fontSize = 11.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp),
        )
        if (trace.effectiveProviders.isNotEmpty() && trace.phase == ProviderTracePhase.Resolved) {
            Text(
                text = trace.effectiveProviders.joinToString(", "),
                color = Color.White.copy(alpha = 0.45f),
                fontSize = 10.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        if (trace.errors.isNotEmpty()) {
            Text(
                text = trace.errors.joinToString(" · "),
                color = Color(0xFFF87171),
                fontSize = 10.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        HorizontalDivider(
            modifier = Modifier.padding(top = 8.dp),
            color = Color.White.copy(alpha = 0.1f)
        )
    }
}

private fun providerPhaseColor(phase: ProviderTracePhase): Color = when (phase) {
    ProviderTracePhase.Resolved -> Color(0xFF60A5FA)
    ProviderTracePhase.CacheMemory, ProviderTracePhase.CacheDisk -> Color(0xFF94A3B8)
    ProviderTracePhase.FetchPlanned -> Color(0xFFA78BFA)
    ProviderTracePhase.FetchStart -> Color(0xFFFACC15)
    ProviderTracePhase.FetchEnd -> Color(0xFF4ADE80)
    ProviderTracePhase.Skipped -> Color(0xFFFB923C)
    ProviderTracePhase.Complete -> Color(0xFF2DD4BF)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProviderTraceDetailsDialog(trace: ProviderTraceEntry, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
        title = {
            Text("${trace.phase.name} — ${trace.provider ?: "POI providers"}", fontWeight = FontWeight.Bold)
        },
        text = {
            SelectionContainer {
                LazyColumn {
                    item {
                        DetailItem("Time", Date(trace.timestamp).toString())
                        DetailItem("Message", trace.message)
                        trace.provider?.let { DetailItem("Provider", it) }
                        trace.poiCount?.let { DetailItem("POI count", it.toString()) }
                        trace.durationMs?.let { DetailItem("Duration", "${it}ms") }
                        if (trace.countries.isNotEmpty()) {
                            DetailItem("Countries", trace.countries.joinToString(", "))
                        }
                        if (trace.categories.isNotEmpty()) {
                            DetailItem("Categories", trace.categories.joinToString(", "))
                        }
                        if (trace.effectiveProviders.isNotEmpty()) {
                            DetailItem("Effective", trace.effectiveProviders.joinToString(", "))
                        }
                        if (trace.fetchedProviders.isNotEmpty()) {
                            DetailItem("Fetched", trace.fetchedProviders.joinToString(", "))
                        }
                        trace.errors.forEach { err ->
                            DetailItem("Error", err)
                        }
                    }
                }
            }
        },
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        modifier = Modifier.fillMaxWidth(0.95f),
    )
}

@Composable
private fun LogItem(log: NetworkLog, onClick: () -> Unit) {
    val time = remember(log.timestamp) {
        SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault()).format(Date(log.timestamp))
    }
    val statusColor = when (log.statusCode) {
        in 200..299 -> Color(0xFF4ADE80)
        in 400..499 -> Color(0xFFFACC15)
        in 500..599 -> Color(0xFFF87171)
        else -> Color.Gray
    }
    val sizeLabel = remember(log.requestSizeBytes, log.responseSizeBytes) {
        formatTransferSizes(log.requestSizeBytes, log.responseSizeBytes)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = log.method,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
                modifier = Modifier
                    .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp, vertical = 2.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = log.statusCode?.toString() ?: "ERR",
                color = statusColor,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "${log.durationMs}ms",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 11.sp
            )
            if (sizeLabel.isNotEmpty()) {
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = sizeLabel,
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = time,
                color = Color.White.copy(alpha = 0.4f),
                fontSize = 10.sp
            )
        }
        Text(
            text = log.url,
            color = Color.White.copy(alpha = 0.8f),
            fontSize = 11.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp)
        )
        HorizontalDivider(
            modifier = Modifier.padding(top = 8.dp),
            color = Color.White.copy(alpha = 0.1f)
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LogDetailsDialog(log: NetworkLog, onDismiss: () -> Unit) {
    var fullscreenBody by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
        title = {
            Text("Request details", fontSize = 18.sp, fontWeight = FontWeight.Bold)
        },
        text = {
            SelectionContainer {
                LazyColumn(modifier = Modifier.fillMaxWidth()) {
                    item {
                        DetailSection("General")
                        DetailItem("URL", log.url)
                        DetailItem("Method", log.method)
                        DetailItem("Status", log.statusCode?.toString() ?: "N/A")
                        DetailItem("Duration", "${log.durationMs}ms")
                        DetailItem("Time", Date(log.timestamp).toString())
                        if (log.requestSizeBytes > 0 || log.responseSizeBytes > 0) {
                            DetailItem(
                                "Size",
                                buildString {
                                    if (log.requestSizeBytes > 0) {
                                        append("↑ ${formatBytes(log.requestSizeBytes)}")
                                    }
                                    if (log.requestSizeBytes > 0 && log.responseSizeBytes > 0) {
                                        append("  ")
                                    }
                                    if (log.responseSizeBytes > 0) {
                                        append("↓ ${formatBytes(log.responseSizeBytes)}")
                                    }
                                }
                            )
                        }

                        val queryParams = remember(log.url) { log.queryParams }
                        if (queryParams.isNotEmpty()) {
                            Spacer(modifier = Modifier.height(16.dp))
                            DetailSection("Query parameters")
                            queryParams.forEach { (k, v) ->
                                val joinedValue = v.joinToString(", ")
                                val jsonElement = remember(joinedValue) {
                                    try { Json.parseToJsonElement(joinedValue) } catch (_: Exception) { null }
                                }
                                if (jsonElement != null && (jsonElement is JsonObject || jsonElement is JsonArray)) {
                                    Row(modifier = Modifier.padding(vertical = 2.dp)) {
                                        Text(
                                            text = "$k: ",
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 12.sp
                                        )
                                    }
                                    JsonTree(
                                        jsonElement = jsonElement,
                                        modifier = Modifier.padding(start = 12.dp, top = 2.dp, bottom = 4.dp)
                                    )
                                } else {
                                    DetailItem(k, joinedValue)
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(16.dp))
                        CollapsibleDetailSection(
                            title = "Request headers",
                            initiallyExpanded = false
                        ) {
                            Column {
                                log.requestHeaders.forEach { (k, v) ->
                                    DetailItem(k, v.joinToString(", "))
                                }
                            }
                        }

                        val reqBody = remember(log.id, log.requestBody) { log.safeRequestBody }
                        if (reqBody.isNotBlank() || log.requestSizeBytes > 0) {
                            Spacer(modifier = Modifier.height(16.dp))
                            val reqTitle = if (log.requestSizeBytes > 0) {
                                "Request body (${formatBytes(log.requestSizeBytes)})"
                            } else {
                                "Request body"
                            }
                            DetailSection(reqTitle)
                            if (reqBody.isNotBlank()) {
                                BodyContent(reqBody, onFullscreen = { fullscreenBody = reqBody })
                            } else {
                                Text(
                                    text = "No body captured (size ${formatBytes(log.requestSizeBytes)})",
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                                )
                            }
                        }

                        log.responseHeaders?.let { headers ->
                            Spacer(modifier = Modifier.height(16.dp))
                            CollapsibleDetailSection(
                                title = "Response headers",
                                initiallyExpanded = false
                            ) {
                                Column {
                                    headers.forEach { (k, v) ->
                                        DetailItem(k, v.joinToString(", "))
                                    }
                                }
                            }
                        }

                        val respBody = remember(log.id, log.responseBody) { log.safeResponseBody }
                        if (respBody.isNotBlank() || log.responseSizeBytes > 0) {
                            Spacer(modifier = Modifier.height(16.dp))
                            val respTitle = if (log.responseSizeBytes > 0) {
                                "Response body (${formatBytes(log.responseSizeBytes)})"
                            } else {
                                "Response body"
                            }
                            DetailSection(respTitle)
                            if (respBody.isNotBlank()) {
                                BodyContent(respBody, onFullscreen = { fullscreenBody = respBody })
                            } else {
                                Text(
                                    text = "No body captured (size ${formatBytes(log.responseSizeBytes)})",
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                                )
                            }
                        }
                    }
                }
            }
        },
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        modifier = Modifier.fillMaxWidth(0.95f).fillMaxHeight(0.8f)
    )

    if (fullscreenBody != null) {
        FullscreenBodyDialog(
            body = fullscreenBody!!,
            onDismiss = { fullscreenBody = null }
        )
    }
}

@Composable
private fun CollapsibleDetailSection(
    title: String,
    initiallyExpanded: Boolean = false,
    content: @Composable () -> Unit
) {
    var expanded by remember { mutableStateOf(initiallyExpanded) }
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = if (expanded) Icons.Default.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = title,
                color = MaterialTheme.colorScheme.primary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
        }
        if (expanded) {
            Box(modifier = Modifier.padding(start = 12.dp)) {
                content()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FullscreenBodyDialog(body: String, onDismiss: () -> Unit) {
    val display = remember(body) { truncateForDisplay(body) }
    val jsonElement = remember(display.text) {
        parseAndLimitJson(display.text)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
        title = {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Body viewer", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    if (display.truncated) {
                        Text(
                            text = "Truncated · ${formatBytes(display.originalLength.toLong())} total",
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        )
                    }
                }
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Close")
                }
            }
        },
        text = {
            SelectionContainer {
                Surface(
                    color = Color.Black.copy(alpha = 0.05f),
                    shape = RoundedCornerShape(8.dp),
                    modifier = Modifier.fillMaxSize()
                ) {
                    if (jsonElement != null) {
                        JsonTree(
                            jsonElement = jsonElement,
                            modifier = Modifier.fillMaxSize().padding(8.dp),
                            initialExpanded = true,
                            useLazyColumn = true
                        )
                    } else {
                        PlainBodyText(
                            text = display.text,
                            modifier = Modifier.fillMaxSize().padding(8.dp),
                            useLazyColumn = true,
                        )
                    }
                }
            }
        },
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        modifier = Modifier.fillMaxSize()
    )
}

@Composable
private fun DetailSection(title: String) {
    Text(
        text = title,
        color = MaterialTheme.colorScheme.primary,
        fontSize = 14.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(vertical = 4.dp)
    )
}

@Composable
private fun DetailItem(label: String, value: String) {
    Row(modifier = Modifier.padding(vertical = 2.dp)) {
        Text(
            text = "$label: ",
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
            modifier = Modifier.width(100.dp)
        )
        Text(text = value, fontSize = 12.sp)
    }
}

@Composable
private fun BodyContent(
    body: String,
    onFullscreen: (() -> Unit)? = null
) {
    val display = remember(body) { truncateForDisplay(body) }
    val jsonElement = remember(display.text) {
        parseAndLimitJson(display.text)
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        if (display.truncated) {
            Text(
                text = "Showing ${formatBytesCompact(MAX_DISPLAY_BODY_CHARS.toLong())} of ${formatBytes(display.originalLength.toLong())} (truncated)",
                fontSize = 10.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                modifier = Modifier.padding(bottom = 4.dp),
            )
        }
        Box(modifier = Modifier.fillMaxWidth()) {
            Surface(
                color = Color.Black.copy(alpha = 0.05f),
                shape = RoundedCornerShape(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                if (jsonElement != null) {
                    JsonTree(
                        jsonElement = jsonElement,
                        modifier = Modifier.padding(8.dp)
                    )
                } else {
                    PlainBodyText(
                        text = display.text,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 240.dp)
                            .padding(8.dp),
                        useLazyColumn = true,
                    )
                }
            }

            if (onFullscreen != null) {
                IconButton(
                    onClick = onFullscreen,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(4.dp)
                        .size(24.dp)
                ) {
                    Icon(
                        Icons.Default.Fullscreen,
                        contentDescription = "Fullscreen",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }
    }
}

/**
 * Renders CSV / plain text / XML / etc. as virtualized monospace lines.
 * Never assumes JSON — callers route structured JSON to [JsonTree] separately.
 */
@Composable
private fun PlainBodyText(
    text: String,
    modifier: Modifier = Modifier,
    useLazyColumn: Boolean = true,
) {
    val lines = remember(text) { bodyLinesForDisplay(text) }
    if (useLazyColumn) {
        LazyColumn(modifier = modifier) {
            items(lines.size, key = { it }) { index ->
                Text(
                    text = lines[index],
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
    } else {
        Text(
            text = lines.joinToString("\n"),
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            modifier = modifier,
        )
    }
}

@Composable
private fun DataConsumptionTab(
    hostConsumptions: List<HostDataConsumption>,
    totalSent: Long,
    totalReceived: Long,
    onResetClick: () -> Unit,
) {
    val totalBytes = totalSent + totalReceived
    var selectedHost by remember { mutableStateOf<String?>(null) }
    val availableHosts = remember(hostConsumptions) {
        hostConsumptions.map { it.host }.filter { it.isNotEmpty() }.distinct().sorted()
    }
    val filteredConsumptions = if (selectedHost == null) {
        hostConsumptions
    } else {
        hostConsumptions.filter { it.host == selectedHost }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            colors = CardDefaults.cardColors(containerColor = Color(0xFF1E293B))
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            "Total consumption",
                            color = Color.White.copy(alpha = 0.6f),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            formatBytes(totalBytes),
                            color = Color.White,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    Button(
                        onClick = onResetClick,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFDC2626)),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.RestartAlt,
                            contentDescription = "Reset",
                            modifier = Modifier.size(16.dp),
                            tint = Color.White
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "Reset",
                            fontSize = 11.sp,
                            color = Color.White
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        "Rx: ${formatBytes(totalReceived)}",
                        color = Color(0xFF4ADE80),
                        fontSize = 11.sp
                    )
                    Text(
                        "Tx: ${formatBytes(totalSent)}",
                        color = Color(0xFF60A5FA),
                        fontSize = 11.sp
                    )
                }
            }
        }

        if (availableHosts.isNotEmpty()) {
            LazyRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    HostFilterChip(
                        label = "All",
                        selected = selectedHost == null,
                        onClick = { selectedHost = null },
                    )
                }
                items(availableHosts) { host ->
                    HostFilterChip(
                        label = host,
                        selected = selectedHost == host,
                        onClick = { selectedHost = if (selectedHost == host) null else host },
                    )
                }
            }
        }

        if (filteredConsumptions.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "No data consumption yet",
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 12.sp,
                )
            }
        } else {
            val maxBytes = remember(filteredConsumptions) {
                filteredConsumptions.maxOfOrNull { it.totalBytes }?.coerceAtLeast(1L) ?: 1L
            }

            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(filteredConsumptions, key = { it.host }) { hostData ->
                    HostConsumptionItem(hostData = hostData, maxBytes = maxBytes)
                }
            }
        }
    }
}

@Composable
private fun HostConsumptionItem(hostData: HostDataConsumption, maxBytes: Long) {
    val fraction = (hostData.totalBytes.toFloat() / maxBytes.toFloat()).coerceIn(0f, 1f)
    val providerName = hostData.providerName

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                if (!providerName.isNullOrBlank()) {
                    Text(
                        text = providerName,
                        color = Color(0xFF93C5FD),
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp
                    )
                    Text(
                        text = hostData.host,
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 11.sp
                    )
                } else {
                    Text(
                        text = hostData.host,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp
                    )
                }
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = formatBytes(hostData.totalBytes),
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp
                )
                Text(
                    text = "${hostData.requestCount} requests",
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 10.sp
                )
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        LinearProgressIndicator(
            progress = { fraction },
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp)),
            color = Color(0xFF38BDF8),
            trackColor = Color.White.copy(alpha = 0.1f)
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Rx: ${formatBytes(hostData.bytesReceived)}",
                color = Color(0xFF4ADE80),
                fontSize = 10.sp
            )
            Text(
                text = "Tx: ${formatBytes(hostData.bytesSent)}",
                color = Color(0xFF60A5FA),
                fontSize = 10.sp
            )
        }

        HorizontalDivider(
            modifier = Modifier.padding(top = 8.dp),
            color = Color.White.copy(alpha = 0.1f)
        )
    }
}

private fun BoxShadow(color: Color) = androidx.compose.foundation.BorderStroke(1.dp, color)
