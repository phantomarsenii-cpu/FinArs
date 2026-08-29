package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import android.util.Log
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.galaxy.GalaxyBillingMode
import com.revenuecat.purchases.galaxy.GalaxyConfiguration
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.restorePurchasesWith

/**
 * Единая точка входа в RevenueCat — определяет магазин установки (Google Play /
 * Galaxy Store / прочее), конфигурирует Purchases SDK нужным ключом и store-специфичным
 * способом, следит за статусом Entitlement "premium" и даёт остальному приложению
 * простой синхронный флаг isProActive().
 *
 * BillingManager.kt — это тонкая обёртка НАД этим сервисом, сохраняющая старые
 * имена методов (isPro/connect/restorePurchases/...), чтобы не трогать экраны,
 * которые уже вызывают BillingManager.
 */
object SubscriptionService {

    private const val TAG = "SubscriptionService"

    // === API-ключи RevenueCat (Project settings -> API keys -> App specific keys) ===

    // Тестовый ключ (RevenueCat Test Store) — им сейчас проверяется весь сценарий покупки
    // (offerings/paywall/purchase/restore) БЕЗ реального биллинга какого-либо магазина.
    // Test Store не привязан к Google Play или Galaxy Store — работает одинаково для обоих.
    private const val TEST_API_KEY = "test_BFXzgXddRkopsjEDdnaRTNtVXuY"

    // Боевые публичные ключи RevenueCat (RevenueCat Dashboard -> Project settings -> API keys).
    // У каждого магазина СВОЙ ключ (goog_ для Google Play, galx_ для Galaxy Store).
    // Используются ТОЛЬКО когда StoreDetector реально определил соответствующий магазин
    // как источник установки — см. buildConfiguration(). При установке не через сам
    // магазин (adb install, тестовая сборка из Termux и т.п.) SDK всё равно уходит на
    // Test Store — это ожидаемо, т.к. ни Google Play, ни Galaxy Store не признают такую
    // установку "своей" и не смогут провести боевую покупку.
    private const val GOOGLE_PLAY_API_KEY = "goog_BCFJgInKuKxeVFyaScMVzMJMqCi"
    private const val GALAXY_STORE_API_KEY = "galx_EKAyCEqEnDpKXmPjQCvobAludwy"

    // Пока идёт тестирование на Galaxy-устройстве через боевой ключ (после того как он появится),
    // GalaxyBillingMode.TEST позволяет проверить покупку без реального списания денег.
    // ВАЖНО: перед сборкой релиза для Galaxy Store — переключить на GalaxyBillingMode.PRODUCTION.
    private val GALAXY_BILLING_MODE_FOR_TESTING = GalaxyBillingMode.TEST

    /**
     * Идентификатор Entitlement в RevenueCat Dashboard, дающий доступ ко всем Pro-функциям
     * приложения (единый доступ и для месячной, и для годовой подписки).
     * TODO: сверить точное название с RevenueCat Dashboard -> Entitlements (сейчас "premium").
     */
    const val ENTITLEMENT_ID = "FinArs Pro"

    private const val OFFERING_ID = "default"

    // Идентификаторы пакетов внутри Offering "default" — стандартные RevenueCat-пакеты
    // (видны в Dashboard как "$rc_monthly" / "$rc_yearly", см. Update-40 offering).
    const val PACKAGE_MONTHLY = "\$rc_monthly"
    const val PACKAGE_YEARLY = "\$rc_annual"

    private const val PREFS_NAME = "settings"
    private const val KEY_IS_PRO_RC = "isProRevenueCat"

    /**
     * amountMicros/currencyCode — «сырая» цена без форматирования (цена, которую Google Play /
     * Galaxy Store реально показывают пользователю, УЖЕ с учётом локального налога/VAT).
     * Нужны, чтобы посчитать эквивалент "в месяц" для годового плана в правильной валюте
     * пользователя, а не полагаться на один захардкоженный курс/налог (см. Update-67).
     */
    data class PlanInfo(
        val price: String,
        val trialDays: Int?,
        val amountMicros: Long,
        val currencyCode: String
    )

    private var initialized = false
    private var cachedOffering: Offering? = null

    /** Магазин, из которого определено, что установлено текущее приложение. */
    var detectedStore: StoreSource = StoreSource.OTHER
        private set

    private val proStatusListeners = mutableListOf<(Boolean) -> Unit>()

    fun addProStatusListener(listener: (Boolean) -> Unit) {
        proStatusListeners.add(listener)
    }

    fun removeProStatusListener(listener: (Boolean) -> Unit) {
        proStatusListeners.remove(listener)
    }

    /** Вызывать один раз при старте приложения — из FaApp.onCreate(). */
    fun init(context: Context) {
        if (initialized) return
        initialized = true

        detectedStore = StoreDetector.detect(context)
        Log.i(TAG, "Detected install source: $detectedStore")

        Purchases.logLevel = LogLevel.DEBUG
        Purchases.configure(buildConfiguration(context))

        // Слушатель обновлений CustomerInfo — сработает при покупке/восстановлении/
        // периодической сверке статуса подписки в течение жизни приложения.
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { info ->
            applyCustomerInfo(context, info)
        }

        // Подхватываем закэшированный статус сразу при старте, не дожидаясь первого
        // события updatedCustomerInfoListener (оно может не прийти, если ничего не изменилось).
        Purchases.sharedInstance.getCustomerInfoWith(
            onError = { error -> Log.w(TAG, "getCustomerInfo failed: ${error.message}") },
            onSuccess = { info -> applyCustomerInfo(context, info) }
        )
    }

    /**
     * Выбирает конфигурацию SDK в зависимости от того, откуда установлено приложение:
     * - Установлено из Google Play -> покупки идут через Google Play Billing.
     * - Установлено из Galaxy Store -> покупки идут через Samsung IAP (GalaxyConfiguration).
     * - Иначе (adb install / сборка для разработки) -> Test Store, чтобы можно было
     *   тестировать весь сценарий на любом устройстве без реального магазина.
     *
     * Пока боевые ключи (GOOGLE_PLAY_API_KEY / GALAXY_STORE_API_KEY) не заданы, всегда
     * используется Test Store — так безопаснее: приложение никогда случайно не попытается
     * достучаться до боевого проекта RevenueCat без настроенного ключа.
     */
    private fun buildConfiguration(context: Context): PurchasesConfiguration {
        val appContext = context.applicationContext
        val useGalaxy = detectedStore == StoreSource.GALAXY_STORE && GALAXY_STORE_API_KEY.isNotBlank()
        val useGooglePlay = detectedStore == StoreSource.GOOGLE_PLAY && GOOGLE_PLAY_API_KEY.isNotBlank()

        return when {
            useGalaxy -> {
                Log.i(TAG, "Configuring RevenueCat for Galaxy Store")
                GalaxyConfiguration.Builder(appContext, GALAXY_STORE_API_KEY, GALAXY_BILLING_MODE_FOR_TESTING)
                    .build()
            }
            useGooglePlay -> {
                Log.i(TAG, "Configuring RevenueCat for Google Play")
                PurchasesConfiguration.Builder(appContext, GOOGLE_PLAY_API_KEY).build()
            }
            else -> {
                Log.i(TAG, "Configuring RevenueCat with Test Store key (real store keys not set yet)")
                PurchasesConfiguration.Builder(appContext, TEST_API_KEY).build()
            }
        }
    }

    private fun applyCustomerInfo(context: Context, info: CustomerInfo) {
        val isPro = info.entitlements[ENTITLEMENT_ID]?.isActive == true
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_IS_PRO_RC, isPro).apply()
        proStatusListeners.forEach { it(isPro) }
    }

    /** Быстрая локальная проверка (кэш) — используйте её для скрытия/показа Pro-функций в UI. */
    fun isProActive(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getBoolean(KEY_IS_PRO_RC, false)

    /** Загружает Offering "default" (или текущий, если "default" не настроен) и кэширует его. */
    fun fetchOfferings(onResult: (offering: Offering?, errorMessage: String?) -> Unit) {
        Purchases.sharedInstance.getOfferingsWith(
            onError = { error ->
                val msg = "getOfferings failed: ${error.message} (${error.underlyingErrorMessage})"
                Log.e(TAG, msg)
                onResult(null, msg)
            },
            onSuccess = { offerings: Offerings ->
                // Отладочный лог: список всех офферингов и их пакетов, полученных от RevenueCat —
                // полезно, если "default" или конкретный пакет не находится.
                Log.i(TAG, "Offerings received: all=${offerings.all.keys}, current=${offerings.current?.identifier}")
                offerings.all.values.forEach { off ->
                    Log.i(TAG, "  Offering '${off.identifier}' packages=${off.availablePackages.map { it.identifier }}")
                }
                val offering = offerings.getOffering(OFFERING_ID) ?: offerings.current
                cachedOffering = offering
                if (offering == null) {
                    val msg = "Offering '$OFFERING_ID' not found and no current offering set. Available: ${offerings.all.keys}"
                    Log.e(TAG, msg)
                    onResult(null, msg)
                } else {
                    onResult(offering, null)
                }
            }
        )
    }

    /** Достаёт цену и длину триала для месячного/годового пакета из последнего загруженного Offering. */
    fun planInfoFor(packageIdentifier: String): PlanInfo? {
        val pkg = findPackage(packageIdentifier) ?: return null
        val product = pkg.product
        val trialPhase = product.subscriptionOptions?.freeTrial?.freePhase
        val trialDays = trialPhase?.billingPeriod?.let { periodToDays(it) }
        return PlanInfo(
            price = product.price.formatted,
            trialDays = trialDays,
            amountMicros = product.price.amountMicros,
            currencyCode = product.price.currencyCode
        )
    }

    private fun periodToDays(period: Period): Int? = when (period.unit) {
        Period.Unit.DAY -> period.value
        Period.Unit.WEEK -> period.value * 7
        Period.Unit.MONTH -> period.value * 30
        Period.Unit.YEAR -> period.value * 365
        else -> null
    }

    fun findPackage(identifier: String): Package? {
        val pkg = cachedOffering?.availablePackages?.firstOrNull { it.identifier == identifier }
        if (pkg == null) {
            Log.w(
                TAG,
                "findPackage('$identifier') = null. cachedOffering='${cachedOffering?.identifier}', " +
                    "available=${cachedOffering?.availablePackages?.map { it.identifier }}"
            )
        }
        return pkg
    }

    /**
     * Покупка пакета (месяц/год). RevenueCat сам определяет, через какой магазин делать
     * покупку — тот же, которым была сконфигурирована SDK (см. buildConfiguration()),
     * т.е. ВСЕГДА магазин, из которого установлено приложение.
     */
    fun purchase(activity: Activity, packageIdentifier: String, onResult: (success: Boolean, errorMessage: String?, userCancelled: Boolean) -> Unit) {
        val pkg = findPackage(packageIdentifier)
        if (pkg == null) {
            val available = cachedOffering?.availablePackages?.map { it.identifier }
            onResult(false, "Package not found: $packageIdentifier. Offering='${cachedOffering?.identifier}', available=$available", false)
            return
        }
        val params = PurchaseParams.Builder(activity, pkg).build()
        Purchases.sharedInstance.purchaseWith(
            purchaseParams = params,
            onError = { error, userCancelled ->
                onResult(false, error.message, userCancelled)
            },
            onSuccess = { _, customerInfo ->
                applyCustomerInfo(activity, customerInfo)
                val isPro = isProActive(activity)
                val diag = if (!isPro) {
                    "Purchase succeeded, but entitlement '$ENTITLEMENT_ID' is not active. " +
                        "Active entitlements: ${customerInfo.entitlements.active.keys}. " +
                        "All entitlements on this customer: ${customerInfo.entitlements.all.keys}"
                } else null
                Log.i(TAG, "Purchase success. isPro=$isPro. active=${customerInfo.entitlements.active.keys}, all=${customerInfo.entitlements.all.keys}")
                onResult(true, diag, false)
            }
        )
    }

    /** Восстановление покупок — вызывать ТОЛЬКО по действию пользователя (кнопка "Восстановить"). */
    fun restorePurchases(context: Context, onResult: (isPro: Boolean) -> Unit) {
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { error ->
                Log.w(TAG, "restorePurchases failed: ${error.message}")
                onResult(isProActive(context))
            },
            onSuccess = { info ->
                applyCustomerInfo(context, info)
                onResult(isProActive(context))
            }
        )
    }
}
