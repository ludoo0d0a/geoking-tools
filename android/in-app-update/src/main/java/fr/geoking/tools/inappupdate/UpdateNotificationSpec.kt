package fr.geoking.tools.inappupdate

import android.app.Activity
import androidx.annotation.DrawableRes

/**
 * App-supplied copy + target activity for the shared “update available” notification.
 * Tap opens [launchActivityClass] with [InAppUpdateIntents.EXTRA_START_UPDATE]=true.
 */
data class UpdateNotificationSpec(
    val channelId: String,
    val channelName: String,
    @DrawableRes val smallIcon: Int,
    val title: String,
    val message: String,
    val launchActivityClass: Class<out Activity>,
    val notificationId: Int = DEFAULT_NOTIFICATION_ID,
) {
    companion object {
        const val DEFAULT_NOTIFICATION_ID = 0x6B5F_5570 // "gkUp"
    }
}
