package com.nivorasr.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.UpdateAvailability
import java.util.Locale

// A FragmentActivity because local_auth's BiometricPrompt needs one (round 3 app lock).
class MainActivity : FlutterFragmentActivity() {
    private var pendingPay: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // UPI (R9, R4.3): open a UPI app with a upi://pay intent and hand back its response
        // string. Only upi://pay is accepted, so this channel can never open a browser or any
        // other link. The response is a hint; the server never trusts it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apnivaas/upi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installed" -> {
                        val wanted = call.argument<List<String>>("packages") ?: emptyList()
                        result.success(wanted.filter { canPay(it) })
                    }
                    "pay" -> pay(call.argument<String>("uri"), call.argument<String>("package"), result)
                    else -> result.notImplemented()
                }
            }
        // Round 6: the Play Store and Google Maps, as apps. "openStore" opens this app's own
        // listing in the Play Store app and "openMap" a geo: pin in a maps app. Neither builds an
        // https link, so neither can ever land in a browser.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apnivaas/apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkUpdate" -> checkUpdate(result)
                    "openStore" -> result.success(openStore())
                    "openMap" -> result.success(
                        openMap(call.argument<Double>("lat"), call.argument<Double>("lng"), call.argument<String>("label"))
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /** Asks Google Play whether a newer build of this app is published. Never throws to Dart. */
    private fun checkUpdate(result: MethodChannel.Result) {
        var answered = false
        fun answer(value: Map<String, Any?>) {
            if (answered) return
            answered = true
            result.success(value)
        }
        try {
            AppUpdateManagerFactory.create(this).appUpdateInfo
                .addOnSuccessListener { info ->
                    val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE ||
                        info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                    answer(mapOf("available" to available, "versionCode" to info.availableVersionCode()))
                }
                // A build not installed from Play (a sideloaded APK) lands here: nothing to say.
                .addOnFailureListener { answer(mapOf("available" to false)) }
        } catch (e: Exception) {
            answer(mapOf("available" to false))
        }
    }

    private fun openStore(): Boolean {
        val listing = Uri.parse("market://details?id=$packageName")
        for (pkg in listOf("com.android.vending", null)) {
            val view = Intent(Intent.ACTION_VIEW, listing).apply {
                if (pkg != null) setPackage(pkg)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (view.resolveActivity(packageManager) == null) continue
            try {
                startActivity(view)
                return true
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            }
        }
        return false
    }

    private fun openMap(lat: Double?, lng: Double?, label: String?): Boolean {
        if (lat == null || lng == null || lat !in -90.0..90.0 || lng !in -180.0..180.0) return false
        val at = String.format(Locale.ROOT, "%.6f,%.6f", lat, lng)
        val name = (label ?: "").replace(Regex("[()\n\r]"), " ").take(80).trim()
        val pin = Uri.parse("geo:$at?q=" + Uri.encode(if (name.isEmpty()) at else "$at($name)"))
        for (pkg in listOf("com.google.android.apps.maps", null)) {
            val view = Intent(Intent.ACTION_VIEW, pin).apply { if (pkg != null) setPackage(pkg) }
            if (view.resolveActivity(packageManager) == null) continue
            try {
                startActivity(view)
                return true
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            }
        }
        return false
    }

    private fun payIntent(pkg: String?): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay")).apply { if (pkg != null) setPackage(pkg) }

    private fun canPay(pkg: String): Boolean =
        pkg.matches(Regex("^[a-zA-Z0-9._]{3,100}$")) &&
            payIntent(pkg).resolveActivity(packageManager) != null

    private fun pay(raw: String?, pkg: String?, result: MethodChannel.Result) {
        val uri = Uri.parse(raw ?: "")
        if (uri.scheme != "upi" || uri.host != "pay" || (pkg != null && !canPay(pkg))) {
            result.success(mapOf("opened" to false))
            return
        }
        val view = Intent(Intent.ACTION_VIEW, uri).apply { if (pkg != null) setPackage(pkg) }
        if (view.resolveActivity(packageManager) == null) {
            result.success(mapOf("opened" to false))
            return
        }
        // A second tap while a UPI app is still open settles the first call without a response.
        pendingPay?.success(mapOf("opened" to true))
        pendingPay = result
        try {
            val launch = if (pkg != null) view else Intent.createChooser(view, "Pay with")
            @Suppress("DEPRECATION")
            startActivityForResult(launch, UPI_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pendingPay = null
            result.success(mapOf("opened" to false))
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != UPI_REQUEST) return
        val response = data?.getStringExtra("response")?.take(2000)
        pendingPay?.success(mapOf("opened" to true, "response" to response))
        pendingPay = null
    }

    companion object {
        private const val UPI_REQUEST = 4207
    }
}
