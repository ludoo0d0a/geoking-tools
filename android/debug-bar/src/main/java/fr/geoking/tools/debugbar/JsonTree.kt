package fr.geoking.tools.debugbar

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private const val MAX_JSON_CONTAINER_ITEMS = 20

private data class JsonNode(
    val path: String,
    val key: String?,
    val value: JsonElement,
    val depth: Int,
    val truncatedItemCount: Int? = null
)

@Composable
fun JsonTree(
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
                        value.entries.forEach { (k, v) ->
                            collectNodes("$path/$k", k, v, depth + 1)
                        }
                    }
                    is JsonArray -> {
                        value.forEachIndexed { i, v ->
                            collectNodes("$path/$i", i.toString(), v, depth + 1)
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
