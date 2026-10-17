package com.example.starter

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.File

/**
 * iOS AppDelegate'teki share kanalının Android karşılığı.
 * ShareActivity paylaşılanları pending_shares.json dosyasına yazar,
 * Flutter (lib/services/share_service.dart) buradan tek tek okur.
 *
 * FlutterFragmentActivity: RevenueCat paywall ekranı bunu zorunlu kılar.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "app.starter/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            val file = File(filesDir, ShareActivity.QUEUE_FILE)
            when (call.method) {
                "popSharedPayload" -> {
                    val array = readQueue(file)
                    if (array.length() == 0) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val first = array.getJSONObject(0)
                    val remaining = JSONArray()
                    for (i in 1 until array.length()) {
                        remaining.put(array.getJSONObject(i))
                    }
                    file.writeText(remaining.toString())

                    val map = mutableMapOf<String, Any?>()
                    first.keys().forEach { k -> map[k] = first.get(k) }
                    result.success(map)
                }
                "hasQueuedShares" -> result.success(readQueue(file).length() > 0)
                "clearSharedPayloadQueue" -> {
                    if (file.exists()) file.delete()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readQueue(file: File): JSONArray {
        if (!file.exists()) return JSONArray()
        return try { JSONArray(file.readText()) } catch (e: Exception) { JSONArray() }
    }
}
