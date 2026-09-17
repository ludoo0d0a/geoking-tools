package fr.geoking.tools.debugbar.model

data class HostDataConsumption(
    val host: String,
    val providerName: String? = null,
    val bytesSent: Long = 0L,
    val bytesReceived: Long = 0L,
    val requestCount: Int = 0,
) {
    val totalBytes: Long get() = bytesSent + bytesReceived
}

data class NetworkLog(
    val id: String,
    val url: String,
    val host: String,
    val method: String,
    val requestHeaders: Map<String, List<String>>,
    val requestBody: String?,
    val responseHeaders: Map<String, List<String>>?,
    val responseBody: String?,
    val statusCode: Int?,
    val durationMs: Long,
    val timestamp: Long,
    val requestSizeBytes: Long = 0,
    val responseSizeBytes: Long = 0,
) {
    val safeRequestBody: String get() = requestBody ?: ""
    val safeResponseBody: String get() = responseBody ?: ""

    val queryParams: Map<String, List<String>> get() = parseQueryParams(url)
}

fun parseQueryParams(url: String): Map<String, List<String>> {
    val queryIndex = url.indexOf('?')
    if (queryIndex == -1) return emptyMap()
    val fragmentIndex = url.indexOf('#', queryIndex)
    val queryString = if (fragmentIndex != -1) {
        url.substring(queryIndex + 1, fragmentIndex)
    } else {
        url.substring(queryIndex + 1)
    }
    if (queryString.isBlank()) return emptyMap()

    val map = mutableMapOf<String, MutableList<String>>()
    queryString.split('&', ';').forEach { param ->
        if (param.isNotBlank()) {
            val parts = param.split('=', limit = 2)
            val key = decodeUrlComponent(parts[0])
            val value = if (parts.size > 1) decodeUrlComponent(parts[1]) else ""
            if (key.isNotEmpty()) {
                map.getOrPut(key) { mutableListOf() }.add(value)
            }
        }
    }
    return map
}

private fun decodeUrlComponent(s: String): String {
    val result = StringBuilder()
    var i = 0
    val bytes = mutableListOf<Byte>()

    fun flushBytes() {
        if (bytes.isNotEmpty()) {
            result.append(bytes.toByteArray().decodeToString())
            bytes.clear()
        }
    }

    while (i < s.length) {
        when (val c = s[i]) {
            '+' -> {
                flushBytes()
                result.append(' ')
                i++
            }
            '%' -> {
                if (i + 2 < s.length) {
                    val b = s.substring(i + 1, i + 3).toIntOrNull(16)
                    if (b != null) {
                        bytes.add(b.toByte())
                        i += 3
                    } else {
                        flushBytes()
                        result.append('%')
                        i++
                    }
                } else {
                    flushBytes()
                    result.append('%')
                    i++
                }
            }
            else -> {
                flushBytes()
                result.append(c)
                i++
            }
        }
    }
    flushBytes()
    return result.toString()
}
