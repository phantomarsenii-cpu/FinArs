package com.example.fa_ksiegowy

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Ежедневная фоновая проверка лимитов и сроков, запускается через WorkManager
 * (переживает перезапуски устройства и не требует, чтобы приложение было открыто).
 * Уведомления показываются не чаще одного раза в день на каждый повод — состояние
 * "уже показали сегодня" хранится в prefs, чтобы не спамить пользователя при
 * каждом запуске воркера.
 */
class LimitsNotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        try {
            val limits = LimitsHelper.compute(applicationContext)
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val today = SDF_DAY.format(java.util.Date())

            // 1) Лимит działalności nierejestrowanej — 80% / 95% / превышение.
            if (limits.activityType == ActivityType.NIEZAREJESTROWANA) {
                val m = limits.monthly
                when {
                    m.exceeded -> notifyOnce(
                        prefs, "n_exceeded_$today",
                        applicationContext.getString(R.string.notif_limit_exceeded_title),
                        applicationContext.getString(R.string.notif_limit_exceeded_text)
                    )
                    m.percent >= 95 -> notifyOnce(
                        prefs, "n_95_$today",
                        applicationContext.getString(R.string.notif_limit_95_title),
                        applicationContext.getString(R.string.notif_limit_95_text)
                    )
                    m.percent >= 80 -> notifyOnce(
                        prefs, "n_80_$today",
                        applicationContext.getString(R.string.notif_limit_80_title),
                        applicationContext.getString(R.string.notif_limit_80_text)
                    )
                }
            }

            // 2) Приближение к порогу 120 000 zł (переход на 32%).
            if (limits.bracket.percent in 90..999) {
                notifyOnce(
                    prefs, "bracket90_${TaxHelper.currentYear()}",
                    applicationContext.getString(R.string.notif_bracket_title),
                    applicationContext.getString(R.string.notif_bracket_text)
                )
            }

            // 3) Приближение к лимиту zwolnienia z VAT (200 000 zł).
            if (limits.vat.percent in 90..999) {
                notifyOnce(
                    prefs, "vat90_${TaxHelper.currentYear()}",
                    applicationContext.getString(R.string.notif_vat_title),
                    applicationContext.getString(R.string.notif_vat_text)
                )
            }

            // 4) Напоминание об авансовом платеже — до 20 числа каждого месяца.
            val cal = Calendar.getInstance()
            val day = cal.get(Calendar.DAY_OF_MONTH)
            if (day in 15..20) {
                notifyOnce(
                    prefs, "advance_${cal.get(Calendar.YEAR)}_${cal.get(Calendar.MONTH)}",
                    applicationContext.getString(R.string.notif_advance_title),
                    applicationContext.getString(R.string.notif_advance_text)
                )
            }

            // 5) Напоминание о сроке подачи PIT (15 lutego – 30 kwietnia).
            val month = cal.get(Calendar.MONTH) // 0-based
            if (month == Calendar.FEBRUARY || month == Calendar.MARCH ||
                (month == Calendar.APRIL && day <= 30)
            ) {
                notifyOnce(
                    prefs, "pit_deadline_${cal.get(Calendar.YEAR)}_$month",
                    applicationContext.getString(R.string.notif_pit_deadline_title),
                    applicationContext.getString(R.string.notif_pit_deadline_text)
                )
            }

            return Result.success()
        } catch (e: Exception) {
            return Result.retry()
        }
    }

    private fun notifyOnce(prefs: android.content.SharedPreferences, key: String, title: String, text: String) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        showNotification(applicationContext, key.hashCode(), title, text)
    }

    companion object {
        private val SDF_DAY = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        const val CHANNEL_ID = "fa_limits_channel"
        private const val UNIQUE_WORK_NAME = "fa_limits_daily_check"

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.notif_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = context.getString(R.string.notif_channel_description)
                }
                mgr.createNotificationChannel(channel)
            }
        }

        fun showNotification(context: Context, id: Int, title: String, text: String) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                if (!granted) return
            }
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .build()
            androidx.core.app.NotificationManagerCompat.from(context).apply {
                try {
                    notify(id, notification)
                } catch (e: SecurityException) {
                    // Разрешение отозвано между проверкой и вызовом — просто пропускаем.
                }
            }
        }

        /** Планирует ежедневную проверку лимитов/сроков. Безопасно вызывать при каждом запуске приложения. */
        fun schedule(context: Context) {
            createChannel(context)
            val request = PeriodicWorkRequestBuilder<LimitsNotificationWorker>(24, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }
    }
}
