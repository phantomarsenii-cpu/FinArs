package com.example.fa_ksiegowy

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Ежедневная фоновая проверка шаблонов регулярных транзакций (аренда, подписки
 * и т.п.). Для каждого шаблона, чей nextRunMillis уже наступил, создаётся
 * обычная запись Entry (как если бы её добавили вручную) и nextRunMillis
 * сдвигается на следующий месяц (тот же day-of-month).
 */
class RecurringEntryWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val db = AppDatabase.getInstance(applicationContext)
            val recurringDao = db.recurringEntryDao()
            val entryDao = db.entryDao()
            val now = System.currentTimeMillis()

            val due = recurringDao.getDue(now)
            for (template in due) {
                entryDao.insert(
                    Entry(
                        amount = template.amount,
                        isIncome = template.isIncome,
                        comment = template.comment,
                        dateMillis = template.nextRunMillis,
                        receiptPath = null
                    )
                )
                recurringDao.update(template.copy(nextRunMillis = nextMonthMillis(template.nextRunMillis, template.dayOfMonth)))
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun nextMonthMillis(fromMillis: Long, dayOfMonth: Int): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = fromMillis }
        cal.add(Calendar.MONTH, 1)
        cal.set(Calendar.DAY_OF_MONTH, dayOfMonth.coerceIn(1, 28))
        cal.set(Calendar.HOUR_OF_DAY, 12)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    companion object {
        private const val UNIQUE_WORK_NAME = "fa_recurring_entries_daily_check"

        /** Планирует ежедневную проверку шаблонов регулярных транзакций. Безопасно вызывать при каждом запуске приложения. */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<RecurringEntryWorker>(24, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }
    }
}
