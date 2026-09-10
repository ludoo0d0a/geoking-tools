package fr.geoking.gaston.ui.map

import fr.geoking.gaston.R
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.ui.draw.scale
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.scale
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import fr.geoking.gaston.CacheManager
import fr.geoking.gaston.shared.logging.DebugLogStore
import fr.geoking.gaston.shared.logging.NetworkLog
import fr.geoking.gaston.shared.logging.ProviderTraceEntry
import fr.geoking.gaston.shared.logging.ProviderTracePhase
import fr.geoking.gaston.shared.logging.ProviderTraceStore
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun DebugLogOverlay(
    modifier: Modifier = Modifier,
    detectedCountries: String? = null,
    onRefresh: (() -> Unit)? = null
) {
    var isExpanded by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        DebugLogOverlayContent(
            isExpanded = isExpanded,
            onExpandedChange = { isExpanded = it },
            detectedCountries = detectedCountries,
            onRefresh = onRefresh,
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
                        detectedCountries = detectedCountries,
                        onRefresh = onRefresh,
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
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DebugLogOverlayContent(
    isExpanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    detectedCountries: String?,
    onRefresh: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    var selectedTab by remember { mutableStateOf(DebugOverlayTab.Network) }
    val settingsManager = org.koin.compose.koinInject<fr.geoking.gaston.SettingsManager>()
    val settings by settingsManager.settings.collectAsState()
    val logs by DebugLogStore.logs.collectAsState()
    val providerTraces by ProviderTraceStore.entries.collectAsState()
    var selectedLog by remember { mutableStateOf<NetworkLog?>(null) }
    var selectedTrace by remember { mutableStateOf<ProviderTraceEntry?>(null) }
    var selectedHost by remember { mutableStateOf<String?>(null) }
    val availableHosts = remember(logs) {
        logs.map { it.host }.filter { it.isNotEmpty() }.distinct().sorted()
    }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    Box(modifier = modifier.zIndex(2f)) {
        if (!isExpanded) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                FloatingActionButton(
                    onClick = { onExpandedChange(true) },
                    containerColor = Color(0xFF334155).copy(alpha = 0.8f),
                    contentColor = Color.White,
                    modifier = Modifier.size(48.dp)
                ) {
                    Icon(Icons.Default.BugReport, contentDescription = stringResource(R.string.action_show_logs))
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
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                when (selectedTab) {
                                    DebugOverlayTab.Network -> "${stringResource(R.string.dashboard_network)} (${logs.size})"
                                    DebugOverlayTab.Providers -> "${stringResource(R.string.debug_overlay_providers)} (${providerTraces.size})"
                                },
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                            )
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TooltipBox(
                                positionProvider = TooltipDefaults.rememberPlainTooltipPositionProvider(),
                                tooltip = { PlainTooltip { Text(stringResource(R.string.settings_debug_disable_cache)) } },
                                state = rememberTooltipState()
                            ) {
                                IconButton(onClick = { settingsManager.setDisableCache(!settings.disableCache) }) {
                                    Icon(
                                        imageVector = if (settings.disableCache) Icons.Default.CloudOff else Icons.Default.Cloud,
                                        contentDescription = stringResource(R.string.settings_debug_disable_cache),
                                        tint = if (settings.disableCache) Color(0xFFF87171) else MaterialTheme.colorScheme.onSurface
                                    )
                                }
                            }
                            IconButton(onClick = {
                                scope.launch {
                                    CacheManager.clearAllCaches(context)
                                    onRefresh?.invoke()
                                }
                            }) {
                                Icon(Icons.Default.Refresh, stringResource(R.string.action_clear_cache_reload), tint = MaterialTheme.colorScheme.onSurface)
                            }
                            IconButton(onClick = { DebugLogStore.clearAll() }) {
                                Icon(Icons.Default.DeleteSweep, stringResource(R.string.settings_clear_logs), tint = MaterialTheme.colorScheme.onSurface)
                            }
                            IconButton(onClick = { onExpandedChange(false) }) {
                                Icon(Icons.Default.Close, stringResource(R.string.action_close), tint = MaterialTheme.colorScheme.onSurface)
                            }
                        }
                    }

                    TabRow(
                        selectedTabIndex = selectedTab.ordinal,
                        containerColor = Color.Transparent,
                        contentColor = Color.White,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    ) {
                        Tab(
                            selected = selectedTab == DebugOverlayTab.Network,
                            onClick = { selectedTab = DebugOverlayTab.Network },
                            text = { Text(stringResource(R.string.dashboard_network), fontSize = 12.sp) },
                        )
                        Tab(
                            selected = selectedTab == DebugOverlayTab.Providers,
                            onClick = { selectedTab = DebugOverlayTab.Providers },
                            text = { Text(stringResource(R.string.debug_overlay_providers), fontSize = 12.sp) },
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
                        label = stringResource(R.string.action_all),
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
                stringResource(R.string.debug_overlay_no_traces),
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
                    text = "$count ${stringResource(R.string.debug_overlay_pois)}",
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
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) }
        },
        title = {
            Text("${trace.phase.name} — ${trace.provider ?: stringResource(R.string.debug_overlay_poi_providers)}", fontWeight = FontWeight.Bold)
        },
        text = {
            SelectionContainer {
                LazyColumn {
                    item {
                        DetailItem(stringResource(R.string.debug_overlay_time), Date(trace.timestamp).toString())
                        DetailItem(stringResource(R.string.debug_overlay_message), trace.message)
                        trace.provider?.let { DetailItem(stringResource(R.string.debug_overlay_provider), it) }
                        trace.poiCount?.let { DetailItem(stringResource(R.string.debug_overlay_poi_count), it.toString()) }
                        trace.durationMs?.let { DetailItem(stringResource(R.string.debug_overlay_duration), "${it}ms") }
                        if (trace.countries.isNotEmpty()) {
                            DetailItem(stringResource(R.string.debug_overlay_countries), trace.countries.joinToString(", "))
                        }
                        if (trace.categories.isNotEmpty()) {
                            DetailItem(stringResource(R.string.debug_overlay_categories), trace.categories.joinToString(", "))
                        }
                        if (trace.effectiveProviders.isNotEmpty()) {
                            DetailItem(stringResource(R.string.debug_overlay_effective), trace.effectiveProviders.joinToString(", "))
                        }
                        if (trace.fetchedProviders.isNotEmpty()) {
                            DetailItem(stringResource(R.string.debug_overlay_fetched), trace.fetchedProviders.joinToString(", "))
                        }
                        trace.errors.forEach { err ->
                            DetailItem(stringResource(R.string.route_error), err)
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
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) }
        },
        title = {
            Text(stringResource(R.string.action_request_details), fontSize = 18.sp, fontWeight = FontWeight.Bold)
        },
        text = {
            SelectionContainer {
                LazyColumn(modifier = Modifier.fillMaxWidth()) {
                    item {
                        DetailSection(stringResource(R.string.debug_overlay_general))
                        DetailItem("URL", log.url)
                        DetailItem(stringResource(R.string.debug_overlay_method), log.method)
                        DetailItem(stringResource(R.string.debug_overlay_status), log.statusCode?.toString() ?: "N/A")
                        DetailItem(stringResource(R.string.debug_overlay_duration), "${log.durationMs}ms")
                        DetailItem(stringResource(R.string.debug_overlay_time), Date(log.timestamp).toString())

                        val queryParams = remember(log.url) { log.queryParams }
                        if (queryParams.isNotEmpty()) {
                            Spacer(modifier = Modifier.height(16.dp))
                            DetailSection(stringResource(R.string.debug_overlay_query_parameters))
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
                        DetailSection(stringResource(R.string.debug_overlay_request_headers))
                        log.requestHeaders.forEach { (k, v) ->
                            DetailItem(k, v.joinToString(", "))
                        }

                        val reqBody = log.safeRequestBody
                        if (reqBody.isNotBlank()) {
                            Spacer(modifier = Modifier.height(16.dp))
                            DetailSection(stringResource(R.string.debug_overlay_request_body))
                            BodyContent(reqBody, onFullscreen = { fullscreenBody = reqBody })
                        }

                        log.responseHeaders?.let { headers ->
                            Spacer(modifier = Modifier.height(16.dp))
                            DetailSection(stringResource(R.string.debug_overlay_response_headers))
                            headers.forEach { (k, v) ->
                                DetailItem(k, v.joinToString(", "))
                            }
                        }

                        val respBody = log.safeResponseBody
                        if (respBody.isNotBlank()) {
                            Spacer(modifier = Modifier.height(16.dp))
                            DetailSection(stringResource(R.string.debug_overlay_response_body))
                            BodyContent(respBody, onFullscreen = { fullscreenBody = respBody })
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FullscreenBodyDialog(body: String, onDismiss: () -> Unit) {
    val jsonElement = remember(body) {
        try {
            Json.parseToJsonElement(body)
        } catch (e: Exception) {
            null
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) }
        },
        title = {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.action_body_viewer), fontSize = 18.sp, fontWeight = FontWeight.Bold)
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = stringResource(R.string.action_close))
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
                        LazyColumn(modifier = Modifier.fillMaxSize().padding(8.dp)) {
                            item {
                                Text(
                                    text = body,
                                    fontSize = 11.sp,
                                    fontFamily = FontFamily.Monospace
                                )
                            }
                        }
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

private data class JsonNode(
    val path: String,
    val key: String?,
    val value: JsonElement,
    val depth: Int,
    val truncatedItemCount: Int = 0
)

private const val MAX_JSON_CONTAINER_ITEMS = 20

@Composable
private fun JsonTree(
    jsonElement: JsonElement,
    modifier: Modifier = Modifier,
    initialExpanded: Boolean = false,
    useLazyColumn: Boolean = false
) {
    val expandedPaths = remember { mutableStateMapOf<String, Boolean>() }

    val nodes = remember(jsonElement, expandedPaths.toMap()) {
        val list = mutableListOf<JsonNode>()
        fun collectNodes(path: String, key: String?, value: JsonElement, depth: Int) {
            list.add(JsonNode(path, key, value, depth))
            val isExpanded = expandedPaths.getOrPut(path) { initialExpanded }
            if (isExpanded) {
                when (value) {
                    is JsonObject -> {
                        val entries = value.entries.toList()
                        val visibleEntries = entries.take(MAX_JSON_CONTAINER_ITEMS)
                        visibleEntries.forEach { (k, v) ->
                            collectNodes("$path/$k", k, v, depth + 1)
                        }
                        if (entries.size > MAX_JSON_CONTAINER_ITEMS) {
                            val truncatedCount = entries.size - MAX_JSON_CONTAINER_ITEMS
                            list.add(
                                JsonNode(
                                    path = "$path/__truncated",
                                    key = null,
                                    value = JsonPrimitive("... ($truncatedCount items truncated)"),
                                    depth = depth + 1,
                                    truncatedItemCount = truncatedCount
                                )
                            )
                        }
                    }
                    is JsonArray -> {
                        val visibleElements = value.take(MAX_JSON_CONTAINER_ITEMS)
                        visibleElements.forEachIndexed { i, v ->
                            collectNodes("$path/$i", i.toString(), v, depth + 1)
                        }
                        if (value.size > MAX_JSON_CONTAINER_ITEMS) {
                            val truncatedCount = value.size - MAX_JSON_CONTAINER_ITEMS
                            list.add(
                                JsonNode(
                                    path = "$path/__truncated",
                                    key = null,
                                    value = JsonPrimitive("... ($truncatedCount items truncated)"),
                                    depth = depth + 1,
                                    truncatedItemCount = truncatedCount
                                )
                            )
                        }
                    }
                    else -> {}
                }
            }
        }
        collectNodes("", null, jsonElement, 0)
        list
    }

    if (useLazyColumn) {
        LazyColumn(modifier = modifier) {
            items(nodes, key = { it.path }) { node ->
                JsonNodeRow(
                    node = node,
                    isExpanded = expandedPaths.getOrPut(node.path) { initialExpanded },
                    onToggle = { expandedPaths[node.path] = !expandedPaths.getOrDefault(node.path, initialExpanded) }
                )
            }
        }
    } else {
        Column(modifier = modifier) {
            nodes.forEach { node ->
                JsonNodeRow(
                    node = node,
                    isExpanded = expandedPaths.getOrPut(node.path) { initialExpanded },
                    onToggle = { expandedPaths[node.path] = !expandedPaths.getOrDefault(node.path, initialExpanded) }
                )
            }
        }
    }
}

@Composable
private fun JsonNodeRow(
    node: JsonNode,
    isExpanded: Boolean,
    onToggle: () -> Unit
) {
    val indent = (node.depth * 12).dp
    val value = node.value

    when (value) {
        is JsonObject, is JsonArray -> {
            val label = when (value) {
                is JsonObject -> if (value.isEmpty()) "{ }" else "{ ... }"
                else -> if ((value as JsonArray).isEmpty()) "[ ]" else "[ ... ]"
            }
            ExpandableNode(
                indent = indent,
                key = node.key,
                label = label,
                isExpanded = isExpanded,
                onToggle = onToggle
            )
        }
        is JsonPrimitive -> {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = indent, top = 2.dp, bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Invisible spacer to align with expandable nodes (which have a 16dp icon)
                Spacer(modifier = Modifier.width(16.dp))
                if (node.key != null) {
                    Text(
                        text = "\"${node.key}\": ",
                        color = Color(0xFF94A3B8),
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold
                    )
                }
                Text(
                    text = if (value.isString) "\"${value.content}\"" else value.content,
                    color = when {
                        value.isString -> Color(0xFF2DD4BF)
                        value.content == "true" || value.content == "false" -> Color(0xFFF472B6)
                        value.content == "null" -> Color(0xFF94A3B8)
                        else -> Color(0xFFFB923C)
                    },
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

@Composable
private fun ExpandableNode(
    indent: Dp,
    key: String?,
    label: String,
    isExpanded: Boolean,
    onToggle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(start = indent, top = 2.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = if (isExpanded) Icons.Default.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.5f),
            modifier = Modifier.size(16.dp)
        )
        if (key != null) {
            Text(
                text = "\"$key\": ",
                color = Color(0xFF94A3B8),
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold
            )
        }
        Text(
            text = label,
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace
        )
    }
}

@Composable
private fun BodyContent(
    body: String,
    onFullscreen: (() -> Unit)? = null
) {
    val jsonElement = remember(body) {
        try {
            Json.parseToJsonElement(body)
        } catch (e: Exception) {
            null
        }
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
                Text(
                    text = body,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.padding(8.dp)
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
                    contentDescription = stringResource(R.string.action_fullscreen),
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}

private fun BoxShadow(color: Color) = androidx.compose.foundation.BorderStroke(1.dp, color)
