package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import java.security.MessageDigest

/**
 * Фасад над SubscriptionService (RevenueCat), сохраняющий исторические имена методов
 * (isPro/connect/restorePurchases/querySubscriptionPlans/launchPurchase), которые уже
 * вызываются из MineActivity, ReportActivity, SettingsActivity, SettingsProActivity и
 * AdsManager. Экраны, которые пользуются BillingManager, менять не пришлось — реальный
 * биллинг теперь идёт через RevenueCat (Google Play Billing ИЛИ Samsung IAP — в
 * зависимости от того, откуда установлено приложение, см. StoreDetector.kt), а не
 * напрямую через com.android.billingclient.
 *
 * Update: миграция с прямого Google Play BillingClient на RevenueCat, с поддержкой
 * единого Pro-доступа для Google Play и Samsung Galaxy Store.
 */
object BillingManager {

    // Исторические ID продуктов из старой (прямой) интеграции с Google Play Billing.
    // Сейчас используются только как публичные константы для UI (SettingsProActivity
    // хранит "какой план выбран" через них) — реальная покупка идёт по RevenueCat
    // package identifier (см. planIdToRcPackage()).
    const val PRO_MONTHLY_PRODUCT_ID = "pro_monthly"
    const val PRO_YEARLY_PRODUCT_ID = "pro_yearly"

    private const val PREFS_NAME = "settings"

    // "Выданный вручную" доступ (промокод разработчика) — независим от RevenueCat.
    // isPro() = ИЛИ(RevenueCat entitlement активен, промокод введён). Это важно: обновления
    // статуса из RevenueCat НЕ должны затирать промокод разработчика, и наоборот.
    private const val KEY_IS_PRO_PROMO = "isProPromo"

    // Код разработчика/тестировщика хранится как SHA-256 хэш, а не открытым текстом,
    // чтобы он не был виден при поверхностном просмотре декомпилированного APK.
    private const val DEV_CODE_SHA256 = "1edc850201cfdf17a41d59873127825355e7a03a3f8c0ab3e550099291844a55"

    private fun planIdToRcPackage(productId: String): String = when (productId) {
        PRO_YEARLY_PRODUCT_ID -> SubscriptionService.PACKAGE_YEARLY
        else -> SubscriptionService.PACKAGE_MONTHLY
    }

    /** Быстрая локальная проверка (кэш) — используйте её для скрытия/показа Pro-функций в UI. */
    fun isPro(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return SubscriptionService.isProActive(context) || prefs.getBoolean(KEY_IS_PRO_PROMO, false)
    }

    /**
     * Ввод кода разработчика/тестировщика — выдаёт Pro локально, без реальной покупки
     * (не связано с RevenueCat).
     * @return true, если код верный и Pro выдан.
     */
    fun tryUnlockWithDevCode(context: Context, code: String): Boolean {
        val hash = sha256(code.trim())
        val ok = hash.equals(DEV_CODE_SHA256, ignoreCase = true)
        if (ok) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_IS_PRO_PROMO, true).apply()
        }
        return ok
    }

    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Инициализирует RevenueCat (если ещё не было сделано в FaApp.onCreate — на всякий
     * случай, это безопасно вызывать повторно) и подгружает Offering "default", чтобы
     * дальше можно было запросить цены/триал через querySubscriptionPlans().
     */
    fun connect(context: Context, onReady: (connected: Boolean) -> Unit) {
        SubscriptionService.init(context)
        SubscriptionService.fetchOfferings { offering ->
            onReady(offering != null)
        }
    }

    /** Подтягивает цену и длину пробного периода обоих планов подписки из RevenueCat. */
    fun querySubscriptionPlans(callback: (monthly: SubscriptionService.PlanInfo?, yearly: SubscriptionService.PlanInfo?) -> Unit) {
        SubscriptionService.fetchOfferings {
            val monthly = SubscriptionService.planInfoFor(SubscriptionService.PACKAGE_MONTHLY)
            val yearly = SubscriptionService.planInfoFor(SubscriptionService.PACKAGE_YEARLY)
            callback(monthly, yearly)
        }
    }

    /**
     * Запускает окно оплаты для выбранного плана (месяц/год). RevenueCat сам определяет,
     * через какой магазин проводить покупку — тот, из которого установлено приложение
     * (Google Play или Samsung Galaxy Store), см. StoreDetector/SubscriptionService.
     *
     * @param onResult success=true, если покупка прошла и Pro активирован; errorMessage
     * заполнен при реальной ошибке (не при отмене пользователем — тогда userCancelled=true
     * и errorMessage=null, чтобы не показывать тост "ошибка" на обычную отмену).
     */
    fun launchPurchase(
        activity: Activity,
        productId: String,
        onResult: (success: Boolean, errorMessage: String?, userCancelled: Boolean) -> Unit = { _, _, _ -> }
    ) {
        SubscriptionService.purchase(activity, planIdToRcPackage(productId), onResult)
    }

    /**
     * Сверяет с сервером RevenueCat, активна ли подписка, и обновляет локальный кэш.
     * Вызывать: при старте экрана Pro и сразу после возврата из окна оплаты.
     */
    fun restorePurchases(context: Context, onResult: (isPro: Boolean) -> Unit) {
        SubscriptionService.restorePurchases(context, onResult)
    }
}
