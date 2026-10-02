package fr.geoking.tools.debugbar.model

/** One row in the Cache tab (type bucket or host). */
data class CacheStatRow(
    val label: String,
    val sizeBytes: Long = 0L,
    val itemCount: Int = 0,
)

/**
 * Snapshot of app caches for the debug-bar Cache tab.
 * Apps fill this from HTTP / image / disk caches; empty defaults keep the UI usable.
 */
data class CacheStats(
    val totalSizeBytes: Long = 0L,
    val totalItemCount: Int = 0,
    /** Breakdown by cache kind (HTTP, Images, Disk, …). */
    val byType: List<CacheStatRow> = emptyList(),
    /** Optional breakdown by host (e.g. OkHttp URL hosts). */
    val byHost: List<CacheStatRow> = emptyList(),
)
