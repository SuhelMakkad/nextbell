package com.suhel.nextbell_platform

import android.Manifest
import android.accounts.Account
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.CustomCredential
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class NextbellPlatformPlugin : FlutterPlugin, ActivityAware, NextbellHostApi,
    PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var authorization: Continuation<AuthorizationResult>? = null
    private var permissionContinuation: Continuation<Unit>? = null
    private val scopes = listOf("openid", "email", "profile", "https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/tasks")
    private val prefs get() = context.getSharedPreferences("nextbell_accounts", Context.MODE_PRIVATE)
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext; NextbellHostApi.setUp(binding.binaryMessenger, this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { NextbellHostApi.setUp(binding.binaryMessenger, null) }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding; activity = binding.activity
        binding.addActivityResultListener(this); binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() { detach() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivity() {
        authorization?.resumeWithException(FlutterError("cancelled", "Google connection was cancelled.")); authorization = null
        permissionContinuation?.resume(Unit); permissionContinuation = null; detach()
    }
    private fun detach() {
        activityBinding?.removeActivityResultListener(this); activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null; activity = null
    }
    private suspend fun authorize(account: Account?, interactive: Boolean, choose: Boolean = false,
        serverClientId: String? = null, includeTasks: Boolean = true): AuthorizationResult {
        val requested = if (includeTasks) scopes else scopes.filterNot { it.endsWith("/tasks") }
        val builder = AuthorizationRequest.builder().setRequestedScopes(requested.map(::Scope))
        if (serverClientId != null) builder.requestOfflineAccess(serverClientId, true)
        if (account != null) builder.setAccount(account)
        if (choose) builder.setPrompt(AuthorizationRequest.Prompt.SELECT_ACCOUNT)
        val result = try { Identity.getAuthorizationClient(context).authorize(builder.build()).await() }
            catch (_: Exception) { throw FlutterError("google_auth", "Google authorization failed. Check OAuth configuration and account access.") }
        if (!result.hasResolution()) return result
        val host = activity
        if (!interactive || host == null) throw FlutterError("reauthorize", "Open Nextbell and reconnect this account.")
        return suspendCancellableCoroutine { continuation ->
            if (authorization != null) { continuation.resumeWithException(FlutterError("busy", "Finish the current connection first.")); return@suspendCancellableCoroutine }
            authorization = continuation
            continuation.invokeOnCancellation { authorization = null }
            try { host.startIntentSenderForResult(result.pendingIntent!!.intentSender, 7301, null, 0, 0, 0) }
            catch (_: Exception) { authorization = null; continuation.resumeWithException(FlutterError("google_auth", "Could not open Google authorization.")) }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 7301) return false
        val continuation = authorization; authorization = null
        if (resultCode != Activity.RESULT_OK || data == null) continuation?.resumeWithException(FlutterError("cancelled", "Google connection was cancelled."))
        else try { continuation?.resume(Identity.getAuthorizationClient(context).getAuthorizationResultFromIntent(data)) }
        catch (_: Exception) { continuation?.resumeWithException(FlutterError("google_auth", "Google authorization did not finish.")) }
        return true
    }
    override suspend fun connect(clientId: String, accountId: String?): NativeAccount {
        val previous = accountId?.let { id -> accounts().firstOrNull { it.id == id } }
        val result = authorize(previous?.let { Account(it.email, "com.google") }, true, previous == null)
        val token = result.accessToken ?: throw FlutterError("google_auth", "Google did not grant access.")
        val user = withContext(Dispatchers.IO) {
            val connection = URL("https://www.googleapis.com/oauth2/v3/userinfo").openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 15000; connection.readTimeout = 15000
                connection.setRequestProperty("Authorization", "Bearer $token")
                if (connection.responseCode != 200) throw FlutterError("google_auth", "Could not read this account.")
                JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            } finally { connection.disconnect() }
        }
        val userId = user.getString("sub")
        if (accountId != null && accountId != userId) throw FlutterError("wrong_account", "Choose the original account when reconnecting.")
        val account = NativeAccount(userId, user.getString("email"), user.optString("name", user.getString("email")))
        prefs.edit().putString(account.id, JSONObject().put("id", account.id).put("email", account.email).put("name", account.name).toString()).commit()
        return account
    }
    override suspend fun accounts(): List<NativeAccount> = prefs.all.values.mapNotNull {
        runCatching { val j = JSONObject(it as String); NativeAccount(j.getString("id"), j.getString("email"), j.getString("name")) }.getOrNull()
    }
    override suspend fun identityToken(serverClientId: String): String {
        val host = activity ?: throw FlutterError("foreground", "Open Nextbell to sign in.")
        try {
            val option = GetSignInWithGoogleOption.Builder(serverClientId).build()
            val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
            val result = CredentialManager.create(host).getCredential(host, request)
            val credential = result.credential
            if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                throw FlutterError("google_auth", "Choose your Google account.")
            }
            return GoogleIdTokenCredential.createFrom(credential.data).idToken
        } catch (_: Exception) { throw FlutterError("google_auth", "Google sign-in did not finish. Please try again.") }
    }
    override suspend fun authorizeCloud(serverClientId: String, email: String, includeTasks: Boolean): String {
        return authorize(Account(email, "com.google"), true, serverClientId = serverClientId,
            includeTasks = includeTasks).serverAuthCode
            ?: throw FlutterError("offline_access", "Allow ongoing Google access to connect this account.")
    }
    override suspend fun configureCloudDevice(alarmsEnabled: Boolean, urgentNotices: Boolean) {
        context.getSharedPreferences("nextbell_cloud", Context.MODE_PRIVATE).edit()
            .putBoolean("alarmsEnabled", alarmsEnabled).putBoolean("urgentNotices", urgentNotices).commit()
    }
    override suspend fun accessToken(accountId: String): String {
        val user = accounts().firstOrNull { it.id == accountId } ?: throw FlutterError("reauthorize", "Reconnect this account.")
        return authorize(Account(user.email, "com.google"), false).accessToken ?: throw FlutterError("reauthorize", "Reconnect this account.")
    }
    override suspend fun removeAccount(accountId: String) { prefs.edit().remove(accountId).commit() }
    override suspend fun permissions() = NativePermissions(AlarmStore(context).canSchedule(),
        NotificationManagerCompat.from(context).areNotificationsEnabled(),
        Build.VERSION.SDK_INT < 34 || context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent())
    override suspend fun requestPermissions(): NativePermissions {
        val host = activity ?: throw FlutterError("foreground", "Open Nextbell to grant permission.")
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            suspendCancellableCoroutine<Unit> { continuation ->
                permissionContinuation = continuation; continuation.invokeOnCancellation { permissionContinuation = null }
                ActivityCompat.requestPermissions(host, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7302)
            }
        }
        if (!AlarmStore(context).canSchedule()) openSettings("alarms")
        else if (!permissions().fullScreen) openSettings("fullscreen")
        return permissions()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != 7302) return false
        permissionContinuation?.resume(Unit); permissionContinuation = null; return true
    }
    override suspend fun openSettings(section: String) {
        val action = when {
            section == "alarms" && Build.VERSION.SDK_INT >= 31 -> Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
            section == "fullscreen" && Build.VERSION.SDK_INT >= 34 -> Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT
            else -> Settings.ACTION_APPLICATION_DETAILS_SETTINGS
        }
        context.startActivity(Intent(action, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    override suspend fun scheduleAlarm(alarm: NativeAlarm) { AlarmStore(context).schedule(alarm) }
    override suspend fun cancelAlarms(ids: List<String>) { AlarmStore(context).cancel(ids) }
    override suspend fun alarms(): List<NativeAlarm> {
        val store = AlarmStore(context); val active = store.active()
        return store.all().filter { it.fireAtMillis > System.currentTimeMillis() || active.contains(it.id) }
            .map { it.copy(ringing = active.contains(it.id)) }
    }
    override suspend fun pendingActions(): List<NativeAlarmAction> = AlarmStore(context).actions()
    override suspend fun acknowledgeActions(ids: List<String>) { AlarmStore(context).acknowledge(ids) }
}
