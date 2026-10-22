package com.puran.societybites

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL_ID = "societybites_orders"
        const val NEW_ORDER_CHANNEL_ID = "societybites_new_orders"
        private const val METHOD_CHANNEL = "societybites/notifications"
        private const val EXTRA_ORDER_ID = "orderId"
        private const val EXTRA_NOTIFICATION_TYPE = "notificationType"
    }

    private var notificationChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()
        notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val title = call.argument<String>("title") ?: "SocietyBites"
                        val body = call.argument<String>("body") ?: ""
                        val urgent = call.argument<Boolean>("urgent") == true
                        val orderId = call.argument<String>("orderId")
                        val notificationType = call.argument<String>("notificationType")
                        showLocalNotification(
                            title,
                            body,
                            urgent,
                            orderId,
                            notificationType,
                        )
                        result.success(null)
                    }
                    "setIncomingOrderWake" -> {
                        val active = call.argument<Boolean>("active") == true
                        setIncomingOrderWake(active)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        deliverLaunchIntentToFlutter()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverLaunchIntentToFlutter()
    }

    private fun deliverLaunchIntentToFlutter() {
        val orderId = intent?.getStringExtra(EXTRA_ORDER_ID)?.trim() ?: return
        val type = intent?.getStringExtra(EXTRA_NOTIFICATION_TYPE)?.trim() ?: return
        if (type != "order_created" || orderId.isEmpty()) return
        notificationChannel?.invokeMethod(
            "launchFromNotification",
            mapOf(
                "orderId" to orderId,
                "notificationType" to type,
            ),
        )
        intent?.removeExtra(EXTRA_ORDER_ID)
        intent?.removeExtra(EXTRA_NOTIFICATION_TYPE)
    }

    private fun setIncomingOrderWake(active: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(active)
            setTurnScreenOn(active)
        }
        val window = window
        if (active) {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        } else {
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)

        val orders = NotificationChannel(
            CHANNEL_ID,
            "Order updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "SocietyBites order and message alerts"
            enableVibration(true)
        }
        manager.createNotificationChannel(orders)

        val alarmAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val newOrders = NotificationChannel(
            NEW_ORDER_CHANNEL_ID,
            "New orders",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Urgent alerts when a neighbor places a new order"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 400)
            setSound(Settings.System.DEFAULT_NOTIFICATION_URI, alarmAttrs)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            setBypassDnd(false)
        }
        manager.createNotificationChannel(newOrders)
    }

    private fun showLocalNotification(
        title: String,
        body: String,
        urgent: Boolean,
        orderId: String?,
        notificationType: String?,
    ) {
        createNotificationChannels()
        val channelId = if (urgent) NEW_ORDER_CHANNEL_ID else CHANNEL_ID
        val type = notificationType?.trim().orEmpty().ifEmpty {
            if (urgent) "order_created" else ""
        }
        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (!orderId.isNullOrBlank()) {
                putExtra(EXTRA_ORDER_ID, orderId)
                if (type.isNotEmpty()) {
                    putExtra(EXTRA_NOTIFICATION_TYPE, type)
                }
            }
        }
        val requestCode = (orderId?.hashCode() ?: System.currentTimeMillis().toInt()) and 0x7fffffff
        val pending = PendingIntent.getActivity(
            this,
            requestCode,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(
                if (urgent) NotificationCompat.PRIORITY_MAX
                else NotificationCompat.PRIORITY_HIGH,
            )
            .setCategory(
                if (urgent) NotificationCompat.CATEGORY_ALARM
                else NotificationCompat.CATEGORY_MESSAGE,
            )
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pending)

        if (urgent) {
            builder
                .setFullScreenIntent(pending, true)
                .setVibrate(longArrayOf(0, 400, 200, 400, 200, 400))
                .setDefaults(NotificationCompat.DEFAULT_SOUND)
        }

        try {
            NotificationManagerCompat.from(this).notify(
                requestCode,
                builder.build(),
            )
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied
        }
    }
}
