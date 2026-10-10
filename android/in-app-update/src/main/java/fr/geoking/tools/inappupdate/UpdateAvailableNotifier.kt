package fr.geoking.tools.inappupdate

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Posts a phone notification for an available Play update.
 * Content tap launches the configured activity with [InAppUpdateIntents.EXTRA_START_UPDATE].
 */
class UpdateAvailableNotifier(
    private val context: Context,
    private val spec: UpdateNotificationSpec,
) {
    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        ensureChannel()
    }

    fun show() {
        if (!canPostNotifications()) return

        val launchIntent = Intent(context, spec.launchActivityClass).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(InAppUpdateIntents.EXTRA_START_UPDATE, true)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            spec.notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, spec.channelId)
            .setSmallIcon(spec.smallIcon)
            .setContentTitle(spec.title)
            .setContentText(spec.message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(spec.message))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
        spec.configureBuilder(builder)

        notificationManager.notify(spec.notificationId, builder.build())
    }

    fun cancel() {
        notificationManager.cancel(spec.notificationId)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val existing = notificationManager.getNotificationChannel(spec.channelId)
        if (existing != null) return
        notificationManager.createNotificationChannel(
            NotificationChannel(
                spec.channelId,
                spec.channelName,
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
