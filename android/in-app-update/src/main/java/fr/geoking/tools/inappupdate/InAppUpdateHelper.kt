package fr.geoking.tools.inappupdate

import android.content.Context
import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Play In-App Updates helper (flexible). Emits [updateAvailable] for a dialog;
 * optionally posts a notification whose tap sets [autoStartUpdate] so the host
 * Activity can call [startUpdate] without an extra confirm.
 * Auto-[completeUpdate] when a flexible download finishes.
 * Manual checks (Settings) can re-prompt and emit [checkFeedback].
 *
 * @param notificationSpec when set, posts a phone notification on availability
 * @param onUpdateAvailableExtra optional hook (e.g. Android Auto HUN) after the
 *   shared phone notification is shown
 */
class InAppUpdateHelper(
    context: Context,
    notificationSpec: UpdateNotificationSpec? = null,
    private val onUpdateAvailableExtra: (() -> Unit)? = null,
) {
    private val appUpdateManager: AppUpdateManager = AppUpdateManagerFactory.create(context)
    private val notifier = notificationSpec?.let { UpdateAvailableNotifier(context, it) }

    private var isUpdateDismissed = false

    private val _updateAvailable = MutableStateFlow<AppUpdateInfo?>(null)
    val updateAvailable: StateFlow<AppUpdateInfo?> = _updateAvailable.asStateFlow()

    private val _installStatus = MutableStateFlow(InstallStatus.UNKNOWN)
    val installStatus: StateFlow<Int> = _installStatus.asStateFlow()

    private val _checkFeedback = MutableStateFlow<CheckFeedback>(CheckFeedback.None)
    val checkFeedback: StateFlow<CheckFeedback> = _checkFeedback.asStateFlow()

    private val _autoStartUpdate = MutableStateFlow(false)
    val autoStartUpdate: StateFlow<Boolean> = _autoStartUpdate.asStateFlow()

    private val installStateListener = InstallStateUpdatedListener { state ->
        _installStatus.value = state.installStatus()
        if (state.installStatus() == InstallStatus.DOWNLOADED) {
            completeUpdate()
        }
    }

    init {
        appUpdateManager.registerListener(installStateListener)
    }

    fun unregister() {
        appUpdateManager.unregisterListener(installStateListener)
    }

    /**
     * Call from Activity [android.app.Activity.onCreate] / [android.app.Activity.onNewIntent].
     * Notification taps set [InAppUpdateIntents.EXTRA_START_UPDATE].
     */
    fun consumeLaunchIntent(intent: Intent?) {
        if (!intent.wantsStartUpdate()) return
        _autoStartUpdate.value = true
        isUpdateDismissed = false
        intent?.removeExtra(InAppUpdateIntents.EXTRA_START_UPDATE)
    }

    /**
     * If the user tapped the update notification and [updateAvailable] is ready,
     * starts the flexible flow. Returns true when started.
     */
    fun maybeAutoStartUpdate(
        launcher: ActivityResultLauncher<IntentSenderRequest>,
    ): Boolean {
        val info = _updateAvailable.value ?: return false
        if (!_autoStartUpdate.value) return false
        startUpdate(info, launcher)
        return true
    }

    /**
     * @param manual When true (Settings), ignores session dismiss, allows re-prompt,
     * and emits [checkFeedback] when already up to date or on error.
     */
    fun checkForUpdate(manual: Boolean = false) {
        if (!manual) {
            if (isUpdateDismissed) return
            if (_updateAvailable.value != null) return
        } else {
            _checkFeedback.value = CheckFeedback.None
            isUpdateDismissed = false
        }

        appUpdateManager.appUpdateInfo
            .addOnSuccessListener { appUpdateInfo ->
                _installStatus.value = appUpdateInfo.installStatus()

                val inProgress = appUpdateInfo.installStatus() == InstallStatus.PENDING ||
                    appUpdateInfo.installStatus() == InstallStatus.DOWNLOADING ||
                    appUpdateInfo.installStatus() == InstallStatus.INSTALLING
                if (inProgress) return@addOnSuccessListener

                if (appUpdateInfo.installStatus() == InstallStatus.DOWNLOADED) {
                    completeUpdate()
                    return@addOnSuccessListener
                }

                if (appUpdateInfo.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                    appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
                ) {
                    _updateAvailable.value = appUpdateInfo
                    notifier?.show()
                    onUpdateAvailableExtra?.invoke()
                    return@addOnSuccessListener
                }

                if (appUpdateInfo.updateAvailability() ==
                    UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS &&
                    appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
                ) {
                    return@addOnSuccessListener
                }

                if (manual) {
                    _checkFeedback.value = CheckFeedback.UpToDate
                }
            }
            .addOnFailureListener { error ->
                if (manual) {
                    _checkFeedback.value = CheckFeedback.Error(
                        error.message ?: "Unknown error",
                    )
                }
            }
    }

    fun startUpdate(
        appUpdateInfo: AppUpdateInfo,
        launcher: ActivityResultLauncher<IntentSenderRequest>,
    ) {
        isUpdateDismissed = true
        _autoStartUpdate.value = false
        notifier?.cancel()
        val options = AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build()
        appUpdateManager.startUpdateFlowForResult(appUpdateInfo, launcher, options)
        _updateAvailable.value = null
    }

    fun completeUpdate() {
        appUpdateManager.completeUpdate()
    }

    fun dismissUpdate() {
        isUpdateDismissed = true
        _autoStartUpdate.value = false
        notifier?.cancel()
        _updateAvailable.value = null
    }

    fun resetCheckFeedback() {
        _checkFeedback.value = CheckFeedback.None
    }
}
