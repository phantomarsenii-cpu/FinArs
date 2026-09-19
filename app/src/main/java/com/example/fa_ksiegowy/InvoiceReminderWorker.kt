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
            // Уведомления должны быть на языке, выбранном В ПРИЛОЖЕНИИ (LocaleHelper),
            // а не на системном языке телефона — раньше ctx.getString(...)
            // брал системную локаль напрямую, из-за чего уведомления могли отличаться
            // от языка интерфейса приложения.
            val ctx = LocaleHelper.applyLocale(applicationContext)
            val dao = AppDatabase.getInstance(applicationContext).invoiceDao()
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val threeDaysMs = 3L * 24 * 60 * 60 * 1000

            val pending = dao.getAll().filter { it.status == InvoiceStatus.PENDING && it.dueDateMillis != null }
            for (inv in pending) {
                val due = inv.dueDateMillis ?: continue
                when {
                    due < now -> LimitsNotificationWorker.notifyRepeatableStatic(
                        applicationContext, prefs, "invoice_overdue_${inv.id}",
                        ctx.getString(R.string.notif_invoice_overdue_title),
                        ctx.getString(R.string.notif_invoice_overdue_text, inv.buyerName, inv.invoiceNumber),
                        InvoiceHistoryActivity::class.java
                    )
                    due - now <= threeDaysMs -> notifyOnce(
                        prefs, "invoice_due_soon_${inv.id}",
                        ctx.getString(R.string.notif_invoice_due_soon_title),
                        ctx.getString(R.string.notif_invoice_due_soon_text, inv.buyerName, inv.invoiceNumber),
                        InvoiceHistoryActivity::class.java
                    )
                }
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun notifyOnce(
        prefs: android.content.SharedPreferences, key: String, title: String, text: String,
        targetActivity: Class<*>? = null
    ) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text, targetActivity)
    }

    companion object {
        private const val UNIQUE_WORK_NAME = "fa_invoice_reminders_daily_check"

        /** Planuje sprawdzanie terminów płatności faktur. Interwał 15 minut (minimum
         *  dopuszczalne dla PeriodicWorkRequest w Androidzie) — nie 1 godzina jak wcześniej.
         *  Update: przy interwale 1h worker fizycznie mógł wysłać maks. ~24
         *  powiadomienia/dzień, niezależnie od częstotliwości ustawionej przez
         *  użytkownika (do 50/dzień, zob. VatComplianceHelper) — realny limit był
         *  dużo niższy niż to, co user mógł ustawić, więc przy wysokiej częstotliwości
         *  powiadomienia prawie się nie pojawiały. 15 minut = do ~96 sprawdzeń/dzień,
         *  z zapasem pokrywa maksymalną częstotliwość 50/dzień.*/
        fun schedule(context: Context) {
            LimitsNotificationWorker.createChannel(context)
            val request = PeriodicWorkRequestBuilder<InvoiceReminderWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }
    }
}
