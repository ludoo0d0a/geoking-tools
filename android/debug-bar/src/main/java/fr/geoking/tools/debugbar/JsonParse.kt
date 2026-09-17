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

internal fun parseAndLimitJson(body: String, maxItems: Int = 20): JsonElement? {
    if (body.isBlank()) return null
    return try {
        val parsed = Json.parseToJsonElement(body)
        limitJsonArrays(parsed, maxItems)
    } catch (_: Throwable) {
        null
    }
}
