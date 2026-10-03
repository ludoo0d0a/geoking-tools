package fr.geoking.tools.debugbar

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Notes appended by Arthur / Gaston capture when a body is char-truncated. */
private val CAPTURE_TRUNCATION_SUFFIX = Regex(
    """(?:\r?\n)?…\s*\[truncated[^\]]*]\s*$""",
)

private const val MAX_PARSE_CHARS = 256 * 1024

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
 * Strip capture/display truncation suffixes that would otherwise break JSON parsing
 * (e.g. `…[truncated 1200 chars]` appended by OkHttp/Ktor debug interceptors).
 */
internal fun stripBodyTruncationNotes(body: String): String =
    body.replace(CAPTURE_TRUNCATION_SUFFIX, "").trimEnd()

/**
 * Best-effort close of truncated JSON so [JsonTree] can still render a partial tree.
 * Only appends `]` / `}` after trimming a broken trailing token — never invents keys.
 */
internal fun salvageTruncatedJson(body: String): String? {
    val s = body.trimEnd().trimEnd(',', ' ', '\t', '\n', '\r')
    if (s.isEmpty()) return null
    val first = s.firstOrNull() ?: return null
    if (first != '{' && first != '[') return null

    var brace = 0
    var bracket = 0
    var inString = false
    var escape = false
    for (c in s) {
        if (inString) {
            when {
                escape -> escape = false
                c == '\\' -> escape = true
                c == '"' -> inString = false
            }
            continue
        }
        when (c) {
            '"' -> inString = true
            '{' -> brace++
            '}' -> brace--
            '[' -> bracket++
            ']' -> bracket--
        }
    }
    if (inString) return null // cut mid-string — too unsafe to close
    if (brace < 0 || bracket < 0) return null
    if (brace == 0 && bracket == 0) return s

    val closers = buildString {
        repeat(bracket) { append(']') }
        repeat(brace) { append('}') }
    }
    return s + closers
}

private fun parseStructuredJson(raw: String): JsonElement? {
    return try {
        when (val parsed = Json.parseToJsonElement(raw)) {
            is JsonObject, is JsonArray -> parsed
            else -> null
        }
    } catch (_: Throwable) {
        null
    }
}

/**
 * Parses [body] as a JSON **object or array** only, then caps array lengths.
 * CSV, plain text, numbers, or quoted strings return null so they render as raw text.
 *
 * Tolerates capture truncation suffixes and partially truncated JSON so the
 * expand/collapse [JsonTree] stays available instead of falling back to plain text.
 */
internal fun parseAndLimitJson(body: String, maxItems: Int = 20): JsonElement? {
    if (body.isBlank()) return null
    val stripped = stripBodyTruncationNotes(body)
    val input =
        if (stripped.length > MAX_PARSE_CHARS) stripped.take(MAX_PARSE_CHARS) else stripped
    val trimmed = input.trimStart()
    val first = trimmed.firstOrNull() ?: return null
    // Only structured JSON — not primitives (would steal CSV / plain text / numbers).
    if (first != '{' && first != '[') return null

    val parsed =
        parseStructuredJson(trimmed)
            ?: salvageTruncatedJson(trimmed)?.let { parseStructuredJson(it) }
            ?: return null
    return limitJsonArrays(parsed, maxItems)
}
