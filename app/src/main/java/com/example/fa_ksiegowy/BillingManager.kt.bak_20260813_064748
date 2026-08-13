package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import android.util.Log
import java.security.MessageDigest
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync

/**
 * Obsluga Google Play Billing dla subskrypcji "Pro" — miesiecznej i rocznej,
 * obie z 7-dniowym darmowym okresem probnym. Wymaga utworzenia w Play Console:
 * Monetize -> Products -> Subscriptions -> Create subscription, z dwoma
 * planami bazowymi (base plans) o podanych ponizej ID produktow, kazdy z
 * doczepiona oferta "Free trial" (7 dni) — sama nazwa produktu w kodzie nie
 * wystarczy, okres probny trzeba skonfigurowac w konsoli.
 */
object BillingManager {

    const val PRO_MONTHLY_PRODUCT_ID = "pro_monthly"
    const val PRO_YEARLY_PRODUCT_ID = "pro_yearly"
    private val SUB_PRODUCT_IDS = listOf(PRO_MONTHLY_PRODUCT_ID, PRO_YEARLY_PRODUCT_ID)
    private const val PREFS_NAME = "settings"

    // Два независимых флага: реальная покупка через Google Play, и "выданный вручную"
    // доступ (промокод разработчика). isPro() = ИЛИ этих двух флагов. Это важно:
    // restorePurchases() должен обновлять ТОЛЬКО первый флаг — иначе он затрёт промокод
    // разработчика при следующей сверке с Google Play (у которого об этом коде ничего не известно).
    private const val KEY_IS_PRO_PURCHASED = "isProPurchased"
    private const val KEY_IS_PRO_PROMO = "isProPromo"

    // Код разработчика/тестировщика хранится как SHA-256 хэш, а не открытым текстом,
    // чтобы он не был виден при поверхностном просмотре декомпилированного APK.
    private const val DEV_CODE_SHA256 = "1edc850201cfdf17a41d59873127825355e7a03a3f8c0ab3e550099291844a55"

    private var billingClient: BillingClient? = null
    private val subProductDetails = mutableMapOf<String, com.android.billingclient.api.ProductDetails>()

    data class PlanInfo(val price: String, val trialDays: Int?)

    private val purchasesUpdatedListener = PurchasesUpdatedListener { result, purchases ->
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            for (purchase in purchases) {
                handlePurchase(purchase)
            }
        }
        // Если пользователь отменил окно оплаты (USER_CANCELED) — просто ничего не делаем.
    }

    /** Быстрая локальная проверка (кэш) — используйте её для скрытия/показа Pro-функций в UI. */
    fun isPro(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_IS_PRO_PURCHASED, false) || prefs.getBoolean(KEY_IS_PRO_PROMO, false)
    }

    private fun setPurchasedLocally(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_IS_PRO_PURCHASED, value).apply()
    }

    /**
     * Ввод кода разработчика/тестировщика — выдаёт Pro локально, без реальной покупки.
     * @return true, если код верный и Pro выдан.
     *
     * ПРИМЕЧАНИЕ: для полноценного тестирования покупок (а не просто разблокировки фич)
     * гораздо правильнее добавить свой email в Play Console -> Monetization setup ->
     * License testing — тогда можно пройти НАСТОЯЩЕЕ окно оплаты бесплатно (\"тестовая карта\").
     * Код ниже — это просто быстрый бэкдор для себя, а не замена нормальному тестированию биллинга.
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

    /** Вызывайте один раз при старте активности, где нужен биллинг (например SettingsProActivity). */
    fun connect(context: Context, onReady: (connected: Boolean) -> Unit) {
        if (billingClient?.isReady == true) {
            onReady(true)
            return
        }
        val client = BillingClient.newBuilder(context.applicationContext)
            .setListener(purchasesUpdatedListener)
            .enablePendingPurchases()
            .build()
        billingClient = client

        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                val ok = result.responseCode == BillingClient.BillingResponseCode.OK
                if (ok) {
                    // При каждом подключении сверяем реальное состояние подписки с Google Play,
                    // а не только с локальным кэшем (на случай новой установки/смены устройства).
                    restorePurchases(context) {}
                }
                onReady(ok)
            }

            override fun onBillingServiceDisconnected() {
                // BillingClient сам не переподключается — переподключение произойдёт
                // при следующем вызове connect().
            }
        })
    }

    /** Подтягивает цену и длину пробного периода обоих планов подписки из Google Play. */
    fun querySubscriptionPlans(callback: (monthly: PlanInfo?, yearly: PlanInfo?) -> Unit) {
        val client = billingClient ?: return callback(null, null)
        val products = SUB_PRODUCT_IDS.map {
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(it)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        }
        val params = QueryProductDetailsParams.newBuilder().setProductList(products).build()

        client.queryProductDetailsAsync(params) { result, productDetailsList ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                subProductDetails.clear()
                productDetailsList.forEach { subProductDetails[it.productId] = it }
                callback(planInfo(PRO_MONTHLY_PRODUCT_ID), planInfo(PRO_YEARLY_PRODUCT_ID))
            } else {
                callback(null, null)
            }
        }
    }

    private fun planInfo(productId: String): PlanInfo? {
        val details = subProductDetails[productId] ?: return null
        val offer = details.subscriptionOfferDetails?.firstOrNull() ?: return null
        // Faza z cena > 0 to wlasciwa cena po okresie probnym; faza z cena 0 to sam trial.
        val paidPhase = offer.pricingPhases.pricingPhaseList.firstOrNull { it.priceAmountMicros > 0 }
            ?: offer.pricingPhases.pricingPhaseList.lastOrNull()
        val trialPhase = offer.pricingPhases.pricingPhaseList.firstOrNull { it.priceAmountMicros == 0L }
        val trialDays = trialPhase?.billingPeriod?.let { parseIsoPeriodDays(it) }
        return PlanInfo(paidPhase?.formattedPrice ?: "—", trialDays)
    }

    /** Bardzo uproszczony parser okresow ISO-8601 uzywanych przez Play Billing (np. "P7D", "P1M", "P1Y"). */
    private fun parseIsoPeriodDays(period: String): Int? {
        val match = Regex("P(\\d+)([DWMY])").find(period) ?: return null
        val n = match.groupValues[1].toIntOrNull() ?: return null
        return when (match.groupValues[2]) {
            "D" -> n
            "W" -> n * 7
            "M" -> n * 30
            "Y" -> n * 365
            else -> null
        }
    }

    /** Запускает окно оплаты Google Play для выбранного плана (месяц/год). */
    fun launchPurchase(activity: Activity, productId: String) {
        val client = billingClient ?: return
        val details = subProductDetails[productId] ?: return
        val offerToken = details.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return

        val productDetailsParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(details)
            .setOfferToken(offerToken)
            .build()
        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productDetailsParams))
            .build()
        client.launchBillingFlow(activity, flowParams)
    }

    private fun handlePurchase(purchase: Purchase) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        if (SUB_PRODUCT_IDS.none { purchase.products.contains(it) }) return

        // Защита от поддельных/подменённых ответов биллинга (см. PurchaseVerifier.kt):
        // не подтверждаем и не засчитываем покупку с невалидной подписью.
        if (!PurchaseVerifier.verify(purchase.originalJson, purchase.signature)) {
            Log.w("BillingManager", "Purchase signature verification FAILED — ignoring purchase")
            return
        }

        if (!purchase.isAcknowledged) {
            val client = billingClient ?: return
            val ackParams = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            client.acknowledgePurchase(ackParams) { }
        }
    }

    /**
     * Сверяет с серверами Google, активна ли подписка (месячная или годовая), и обновляет
     * локальный кэш. Учитываются только покупки с валидной подписью.
     * Вызывать: при старте (после connect) и сразу после возврата из окна оплаты.
     *
     * ВАЖНО: это только клиентская проверка при открытии приложения — если подписка
     * истечёт, пока пользователь не открывает приложение, локальный флаг isPro
     * останется true до следующего вызова restorePurchases(). Для мгновенной реакции
     * на отмену/истечение подписки нужна серверная валидация (Real-time Developer
     * Notifications), что выходит за рамки чисто клиентской реализации.
     */
    fun restorePurchases(context: Context, onResult: (isPro: Boolean) -> Unit) {
        val client = billingClient
        if (client == null || !client.isReady) {
            onResult(isPro(context))
            return
        }
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()

        client.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                val validOwned = purchases.filter { purchase ->
                    SUB_PRODUCT_IDS.any { purchase.products.contains(it) } &&
                        purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                        PurchaseVerifier.verify(purchase.originalJson, purchase.signature)
                }
                setPurchasedLocally(context, validOwned.isNotEmpty())
                validOwned.forEach { handlePurchase(it) }
                onResult(isPro(context))
            } else {
                onResult(isPro(context))
            }
        }
    }
}
