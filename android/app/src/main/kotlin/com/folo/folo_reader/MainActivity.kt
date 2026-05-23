package com.folo.folo_reader

import android.content.ContentProviderClient
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.app.NotificationChannel
import android.app.NotificationManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val MOVE_CHANNEL = "com.autofolo/move_to_background"
    private val BADGE_CHANNEL = "com.autofolo/badge"
    private val BADGE_NOTIFICATION_ID = 1001
    private val BADGE_CHANNEL_ID = "badge_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 退到后台
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MOVE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "moveTaskToBack") {
                val moved = moveTaskToBack(true)
                result.success(moved)
            } else {
                result.notImplemented()
            }
        }

        // 桌面角标
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BADGE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "updateBadge") {
                val count = call.argument<Int>("count") ?: 0
                setBadge(count)
                result.success(null)
            } else if (call.method == "removeBadge") {
                setBadge(0)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setBadge(count: Int) {
        if (tryVivoBadge(count)) return
        fallbackNotificationBadge(count)
    }

    /** Vivo / Origin OS ContentProvider 直写角标，不需要通知 */
    private fun tryVivoBadge(count: Int): Boolean {
        return try {
            val uri = Uri.parse("content://com.vivo.abe.provider.launcher.notification.num")
            var client: ContentProviderClient? = null
            try {
                client = contentResolver.acquireUnstableContentProviderClient(uri)
                if (client != null) {
                    val extra = Bundle().apply {
                        putString("package", packageName)
                        putString("class", "$packageName.${javaClass.simpleName}")
                        putInt("badgenumber", count)
                    }
                    val result = client.call("change_badge", null, extra)
                    val ok = result?.getInt("result") == 0
                    ok
                } else false
            } finally {
                client?.close()
            }
        } catch (_: Exception) {
            false
        }
    }

    /** 通用兜底：发静默通知驱动角标 */
    private fun fallbackNotificationBadge(count: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (count <= 0) {
            nm.cancel(BADGE_NOTIFICATION_ID)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                BADGE_CHANNEL_ID, "桌面角标", NotificationManager.IMPORTANCE_MIN
            ).apply {
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, BADGE_CHANNEL_ID)
            .setContentTitle("未读文章")
            .setContentText("$count 篇未读")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setSilent(true)
            .setOngoing(true)
            .setNumber(count)
            .build()

        nm.notify(BADGE_NOTIFICATION_ID, notification)
    }
}
