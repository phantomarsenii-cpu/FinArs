package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * Update 80: единое место для Pro-ограничений. Раньше диалог "функция Pro" был
 * скопирован в нескольких экранах (и в одном из них проверку просто забыли).
 */
object ProGate {

    /** Бесплатный потолок: приходов и расходов В МЕСЯЦ (каждый тип считается отдельно). */
    const val FREE_ENTRIES_PER_MONTH = 30

    fun isPro(context: Context): Boolean = BillingManager.isPro(context)

    /** Выполняет action, если Pro активен; иначе показывает диалог с переходом на экран подписки. */
    fun require(context: Context, messageRes: Int, action: () -> Unit) {
        if (isPro(context)) action() else showLockedDialog(context, messageRes)
    }

    /** Экран подписки (в меню: Настройки -> Pro версия). */
    fun openPaywall(context: Context) {
        val i = Intent(context, SettingsProActivity::class.java)
        if (context !is Activity) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(i)
    }

    fun showLockedDialog(context: Context, messageRes: Int) {
        AppDialog.show(
            context = context,
            title = "🔒 " + context.getString(R.string.pro_feature_locked_title),
            message = context.getString(messageRes),
            positiveText = context.getString(R.string.pro_gate_subscribe),
            onPositive = { openPaywall(context) },
            negativeText = context.getString(R.string.dialog_close)
        )
    }

    /**
     * true, если без Pro в календарном месяце даты [dateMillis] уже набрано
     * FREE_ENTRIES_PER_MONTH ручных записей данного типа. Вызывать с фонового потока.
     * Записи, созданные фактурами/корректами, в потолок не входят.
     */
    suspend fun freeLimitReached(context: Context, isIncome: Boolean, dateMillis: Long): Boolean {
        if (isPro(context)) return false
        val cal = Calendar.getInstance().apply {
            timeInMillis = dateMillis
            set(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val from = cal.timeInMillis
        cal.add(Calendar.MONTH, 1)
        val to = cal.timeInMillis - 1
        val count = AppDatabase.getInstance(context.applicationContext)
            .entryDao().countManualBetween(isIncome, from, to)
        return count >= FREE_ENTRIES_PER_MONTH
    }
}
