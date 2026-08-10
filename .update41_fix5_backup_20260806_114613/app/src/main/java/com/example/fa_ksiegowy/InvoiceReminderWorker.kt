package com.example.fa_ksiegowy

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Ежедневная проверка неоплаченных (PENDING) фактур. Использует тот же
 * канал уведомлений, что и LimitsNotificationWorker. Каждое напоминание
 * ("скоро срок" / "просрочена") показывается только один раз на фактуру —
 * состояние хранится в prefs, чтобы не спамить при каждом запуске воркера.
 */
class InvoiceReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val dao = AppDatabase.getInstance(applicationContext).invoiceDao()
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val threeDaysMs = 3L * 24 * 60 * 60 * 1000

            val pending = dao.getAll().filter { it.status == InvoiceStatus.PENDING && it.dueDateMillis != null }
            for (inv in pending) {
                val due = inv.dueDateMillis ?: continue
                when {
                    due < now -> notifyOnce(
                        prefs, "invoice_overdue_${inv.id}",
                        applicationContext.getString(R.string.notif_invoice_overdue_title),
                        applicationContext.getString(R.string.notif_invoice_overdue_text, inv.buyerName, inv.invoiceNumber)
                    )
                    due - now <= threeDaysMs -> notifyOnce(
                        prefs, "invoice_due_soon_${inv.id}",
                        applicationContext.getString(R.string.notif_invoice_due_soon_title),
                        applicationContext.getString(R.string.notif_invoice_due_soon_text, inv.buyerName, inv.invoiceNumber)
                    )
                }
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun notifyOnce(prefs: android.content.SharedPreferences, key: String, title: String, text: String) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text)
    }

    companion object {
        private const val UNIQUE_WORK_NAME = "fa_invoice_reminders_daily_check"

        /** Планирует ежедневную проверку сроков оплаты фактур. Безопасно вызывать при каждом запуске приложения. */
        fun schedule(context: Context) {
            LimitsNotificationWorker.createChannel(context)
            val request = PeriodicWorkRequestBuilder<InvoiceReminderWorker>(24, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }
    }
}
