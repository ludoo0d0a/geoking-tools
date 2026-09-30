package fr.geoking.tools.debugbar

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

internal fun limitJsonArrays(element: JsonElement, maxItems: Int = 20): JsonElement {
    return when (element) {
        is JsonObject -> {
            JsonObject(element.mapValues { limitJsonArrays(it.value, maxItems) })
        }
        is JsonArray -> {
            if (element.size > maxItems) {
                val truncatedList = element.take(maxItems).map { limitJsonArrays(it, maxItems) }.toMutableList()
                truncatedList.add(JsonPrimitive("and-more"))
                JsonArray(truncatedList)
            } else {
                JsonArray(element.map { limitJsonArrays(it, maxItems) })
            }
        }
        else -> element
    }
}

/**
 * Parses [body] as a JSON **object or array** only.
 * CSV, plain text, numbers, or quoted strings return null so they render as raw text.
 */
internal fun parseAndLimitJson(body: String, maxItems: Int = 20): JsonElement? {
    if (body.isBlank()) return null
    // Avoid parsing multi-megabyte blobs; caller should truncate first.
    if (body.length > 256 * 1024) return null
    val trimmed = body.trimStart()
    val first = trimmed.firstOrNull() ?: return null
    // Only structured JSON — not primitives (would steal CSV / plain text / numbers).
    if (first != '{' && first != '[') return null
    return try {
        when (val parsed = Json.parseToJsonElement(trimmed)) {
            is JsonObject, is JsonArray -> limitJsonArrays(parsed, maxItems)
            else -> null
        }
    } catch (_: Throwable) {
        null
    }
}
