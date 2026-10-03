package fr.geoking.tools.inappupdate

import android.content.Intent

/** Intent contract for “update available” notification → start flexible update. */
object InAppUpdateIntents {
    const val EXTRA_START_UPDATE = "fr.geoking.tools.inappupdate.EXTRA_START_UPDATE"
}

fun Intent?.wantsStartUpdate(): Boolean =
    this?.getBooleanExtra(InAppUpdateIntents.EXTRA_START_UPDATE, false) == true
