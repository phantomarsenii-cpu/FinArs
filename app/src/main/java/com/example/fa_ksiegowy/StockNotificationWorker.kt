package com.example.fa_ksiegowy

import android.content.Context
import android.content.SharedPreferences
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/** Ежедневная проверка остатков на складе — уведомление раз в день на товар, если остаток низкий. */
class StockNotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            // Уведомления должны быть на языке, выбранном В ПРИЛОЖЕНИИ (LocaleHelper),
            // а не на системном языке телефона — раньше ctx.getString(...)
            // брал системную локаль напрямую, из-за чего уведомления могли отличаться
            // от языка интерфейса приложения.
            val ctx = LocaleHelper.applyLocale(applicationContext)
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            if (!BusinessKindHelper.get(prefs).showsMagazin) return Result.success()
            val dao = AppDatabase.getInstance(applicationContext).productDao()
            val today = SDF_DAY.format(Date())
            for (p in dao.getLowStock()) {
                notifyOnce(
                    prefs, "stock_low_${p.id}_$today",
                    ctx.getString(R.string.notif_low_stock_title),
                    ctx.getString(
                        R.string.notif_low_stock_text,
                        p.name,
                        String.format(Locale.getDefault(), "%.1f", p.quantity),
                        p.unit
                    ),
                    MagazinActivity::class.java
                )
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun notifyOnce(
        prefs: SharedPreferences, key: String, title: String, text: String,
        targetActivity: Class<*>? = null
    ) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text, targetActivity)
    }

    companion object {
        private val SDF_DAY = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        private const val UNIQUE_WORK_NAME = "fa_stock_low_daily_check"

        fun schedule(context: Context) {
            LimitsNotificationWorker.createChannel(context)
            val request = PeriodicWorkRequestBuilder<StockNotificationWorker>(24, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request
            )
        }
    }
}
