package com.example.ia_secretary

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
/**
 * Starts the app when the device boots (and when user taps the launcher icon).
 * The Activity runs with a transparent theme so the secretary runs headless.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON"
        ) {
            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
            }
            context.startActivity(launch)
        }
    }
}
