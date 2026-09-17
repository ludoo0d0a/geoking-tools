package fr.geoking.tools.debugbar.model

enum class ProviderTracePhase {
    Resolved,
    CacheMemory,
    CacheDisk,
    FetchPlanned,
    FetchStart,
    FetchEnd,
    Skipped,
    Complete,
}

data class ProviderTraceEntry(
    val id: String,
    val timestamp: Long,
    val phase: ProviderTracePhase,
    val message: String,
    val effectiveProviders: List<String> = emptyList(),
    val fetchedProviders: List<String> = emptyList(),
    val countries: List<String> = emptyList(),
    val categories: List<String> = emptyList(),
    val provider: String? = null,
    val poiCount: Int? = null,
    val durationMs: Long? = null,
    val errors: List<String> = emptyList(),
)
