package com.nivorasr.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity because local_auth's BiometricPrompt needs one (round 3 app lock).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Round 3 (R9): open a UPI app with a upi://pay intent. Only the upi scheme is
        // accepted, so this channel can never open a browser or any other link.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apnivaas/upi")
            .setMethodCallHandler { call, result ->
                if (call.method != "pay") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = (call.argument<String>("uri") ?: "").let { Uri.parse(it) }
                if (uri.scheme != "upi" || uri.host != "pay") {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val view = Intent(Intent.ACTION_VIEW, uri)
                if (view.resolveActivity(packageManager) == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent.createChooser(view, "Pay with"))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
