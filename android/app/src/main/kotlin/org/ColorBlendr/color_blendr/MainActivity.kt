package org.ColorBlendr.color_blendr

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Google's consent form (UMP) saves the user's privacy choices as IAB
        // strings in the app's default SharedPreferences. The app reads the US
        // opt-out from them and passes it to each mediation network.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.ColorBlendr.color_blendr/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "iabStrings") {
                    result.success(iabStrings())
                } else {
                    result.notImplemented()
                }
            }
    }

    /** Every IAB privacy value (TCF, GPP, US Privacy), as strings. */
    private fun iabStrings(): Map<String, String> {
        // The default SharedPreferences file, as PreferenceManager names it.
        val prefs = getSharedPreferences("${packageName}_preferences", Context.MODE_PRIVATE)
        return prefs.all
            .filterKeys { it.startsWith("IAB") }
            .mapValues { (_, value) -> value.toString() }
    }
}
