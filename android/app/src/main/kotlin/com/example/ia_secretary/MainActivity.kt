package com.example.ia_secretary

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Back and Home send the app to background instead of closing it.
 * bringToFront: no Android 10+ usa só full-screen intent para trazer o app ao frente.
 * Bolha flutuante (overlay): aparece no onStop (app invisível), some no onStart ao voltar.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "ia_secretary"
    private val wakeChannelId = "ia_secretary_wake"
    private var methodChannel: MethodChannel? = null

    private var floatingBubbleEnabled = false
    private var overlayBubbleView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var windowManager: WindowManager? = null
    /// IDs distintos para cada full-screen intent (reutilizar o mesmo id pode falhar na 2.ª ativação).
    private var wakeNotificationSeq = 9000

    companion object {
        const val EXTRA_OPEN_ASSISTANT = "open_assistant"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        windowManager = applicationContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToFront" -> runOnUiThread {
                    bringToFrontInternal()
                    result.success(true)
                }
                "muteRecognitionBeep" -> runOnUiThread {
                    muteRecognitionBeep(true)
                    result.success(true)
                }
                "unmuteRecognitionBeep" -> runOnUiThread {
                    muteRecognitionBeep(false)
                    result.success(true)
                }
                "moveToBack" -> runOnUiThread {
                    moveTaskToBack(true)
                    try {
                        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(homeIntent)
                    } catch (_: Exception) { }
                    result.success(true)
                }
                "setFloatingBubbleEnabled" -> runOnUiThread {
                    floatingBubbleEnabled = call.arguments == true
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Bolha só quando a Activity fica invisível (onPause sozinho dispara com diálogos e podia conflitar com onResume).
    override fun onStop() {
        if (floatingBubbleEnabled && canDrawOverlays()) {
            window?.decorView?.post { showOverlayBubble() } ?: showOverlayBubble()
        }
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        removeOverlayBubble()
    }

    override fun onResume() {
        super.onResume()
        notifyAssistantIfNeeded(intent)
    }

    override fun onDestroy() {
        removeOverlayBubble()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        notifyAssistantIfNeeded(intent)
    }

    private fun canDrawOverlays(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(this)
    }

    private fun notifyAssistantIfNeeded(intent: Intent?) {
        if (intent != null && intent.getBooleanExtra(EXTRA_OPEN_ASSISTANT, false)) {
            intent.removeExtra(EXTRA_OPEN_ASSISTANT)
            runOnUiThread {
                methodChannel?.invokeMethod("showAssistant", null)
            }
        }
    }

    private fun showOverlayBubble() {
        if (windowManager == null) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Referência antiga: view já foi removida pelo sistema → recriar.
        overlayBubbleView?.let { v ->
            try {
                if (v.parent == null) {
                    removeOverlayBubble()
                } else {
                    return
                }
            } catch (_: Exception) {
                removeOverlayBubble()
            }
        }

        val bubbleSizePx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            56f,
            resources.displayMetrics
        ).toInt()
        val labelHeightPx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            20f,
            resources.displayMetrics
        ).toInt()
        val totalWidth = bubbleSizePx + dp(8)
        val totalHeight = bubbleSizePx + labelHeightPx

        val params = WindowManager.LayoutParams(
            totalWidth,
            totalHeight,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dp(8)
            y = resources.displayMetrics.heightPixels / 2 - totalHeight / 2
        }

        val view = createBubbleView(bubbleSizePx, labelHeightPx)
        try {
            windowManager!!.addView(view, params)
            overlayBubbleView = view
            overlayParams = params
        } catch (_: Exception) {
            overlayBubbleView = null
            overlayParams = null
        }
    }

    private fun dp(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createBubbleView(bubbleSizePx: Int, labelHeightPx: Int): View {
        val container = LinearLayout(applicationContext).apply {
            orientation = LinearLayout.VERTICAL
            setGravity(android.view.Gravity.CENTER_HORIZONTAL)
        }
        val imageView = ImageView(applicationContext).apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF00d4ff.toInt())
            }
            setPadding(dp(14), dp(14), dp(14), dp(14))
        }
        imageView.layoutParams = LinearLayout.LayoutParams(bubbleSizePx, bubbleSizePx)
        val label = TextView(applicationContext).apply {
            text = "Ava"
            setTextColor(0xFF00d4ff.toInt())
            textSize = 11f
            setPadding(0, dp(2), 0, 0)
        }
        label.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            labelHeightPx
        )
        container.addView(imageView)
        container.addView(label)

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var moved = false

        container.setOnTouchListener { _, event ->
            val wm = windowManager ?: return@setOnTouchListener false
            val p = overlayParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = p.x
                    initialY = p.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moved = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (kotlin.math.abs(dx) > 10 || kotlin.math.abs(dy) > 10) moved = true
                    // Com Gravity.END, x conta a partir da direita: +x empurra para a esquerda.
                    // Inverter dx para o arrastar acompanhar o dedo.
                    p.x = initialX - dx.toInt()
                    p.y = initialY + dy.toInt()
                    try {
                        val bubble = overlayBubbleView
                        if (bubble != null && bubble.parent != null) {
                            wm.updateViewLayout(bubble, p)
                        }
                    } catch (_: Exception) {
                        removeOverlayBubble()
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        openAssistantFromBubble()
                    }
                }
            }
            false
        }
        return container
    }

    private fun openAssistantFromBubble() {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra(EXTRA_OPEN_ASSISTANT, true)
        }
        startActivity(intent)
    }

    private fun removeOverlayBubble() {
        overlayBubbleView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) { }
            overlayBubbleView = null
            overlayParams = null
        }
    }

    private fun bringToFrontInternal() {
        val openAssistantIntent = Intent(applicationContext, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            putExtra(EXTRA_OPEN_ASSISTANT, true)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            applicationContext,
            0,
            openAssistantIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        createWakeChannel()
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val notification = Notification.Builder(applicationContext, wakeChannelId)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("IA Secretary")
            .setContentText("Toque para abrir a secretária")
            .setContentIntent(fullScreenPendingIntent)
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setAutoCancel(true)
            .build()
        wakeNotificationSeq++
        if (wakeNotificationSeq > 99999) wakeNotificationSeq = 9001
        nm.notify(wakeNotificationSeq, notification)
        // Reforço: em vários OEMs só a notificação não basta na 2.ª vez; tentar trazer a task (pode falhar por BAL — ignorar).
        try {
            applicationContext.startActivity(Intent(applicationContext, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
                putExtra(EXTRA_OPEN_ASSISTANT, true)
            })
        } catch (_: Exception) {
        }
    }

    private fun createWakeChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                wakeChannelId,
                "Secretária",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Ativação por voz"
                setBypassDnd(true)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }

    private fun muteRecognitionBeep(mute: Boolean) {
        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val dir = if (mute) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE
        val streams = intArrayOf(
            AudioManager.STREAM_MUSIC,
            AudioManager.STREAM_NOTIFICATION,
            AudioManager.STREAM_SYSTEM
        )
        for (s in streams) {
            try {
                am.adjustStreamVolume(s, dir, 0)
            } catch (_: Exception) { }
        }
    }

    @Deprecated("Deprecated in API 33; still used so Back moves to background instead of finishing")
    override fun onBackPressed() {
        moveTaskToBack(true)
    }
}
