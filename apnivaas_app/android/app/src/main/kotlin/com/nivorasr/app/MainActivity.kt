package com.nivorasr.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
