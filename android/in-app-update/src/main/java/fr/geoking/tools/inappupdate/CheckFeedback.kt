package fr.geoking.tools.inappupdate

sealed class CheckFeedback {
    data object None : CheckFeedback()
    data object UpToDate : CheckFeedback()
    data class Error(val message: String) : CheckFeedback()
}
