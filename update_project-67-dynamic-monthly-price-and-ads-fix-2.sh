#!/data/data/com.termux/files/usr/bin/bash
# Update 67: две независимые правки.
#
#  1) Плашка "Всего 8,33 zł / месяц" под годовым планом была зашита строкой
#     и не совпадала с реальной ценой после налога (Google Play/Galaxy Store
#     добавляют локальный VAT/GST поверх цены из консоли — у автора цена в
#     консоли 99,99 zł/год, а после налога магазин показывает 124,99 zł/год,
#     т.е. 10,42 zł/месяц, а не 8,33 zł). Теперь плашка считается из РЕАЛЬНОЙ
#     цены, которую вернул RevenueCat (она уже включает налог и работает для
#     любой валюты/региона), а не из захардкоженного числа.
#
#  2) В релизной сборке (.aab) баннер AdMob грузится через боевой
#     PROD_BANNER_UNIT_ID (isDebuggable=false), но нигде не был настроен
#     testDeviceIds — поэтому SDK на устройстве не знал, что оно тестовое,
#     даже если оно добавлено как тестовое в AdMob Dashboard. Для совсем
#     нового боевого рекламного блока это может выглядеть как "реклама
#     пропала" (No Fill). Добавлен явный RequestConfiguration.setTestDeviceIds()
#     перед MobileAds.initialize() — впишите свой хэшированный Device ID
#     из logcat (adb logcat | grep -i "Ads") в TEST_DEVICE_IDS в AdsManager.kt.
#
# Запускать из корня репозитория, например:
#   cd ~/FA_ksiegowy
#   bash update_project-67-dynamic-monthly-price-and-ads-fix.sh

set -e
cd "$(dirname "$0")"
if [ ! -f "app/build.gradle" ]; then
  cd ~/FA_ksiegowy
fi

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update67_backup_${TS}"

SUB_SERVICE="app/src/main/java/com/example/fa_ksiegowy/SubscriptionService.kt"
SETTINGS_PRO="app/src/main/java/com/example/fa_ksiegowy/SettingsProActivity.kt"
ADS_MANAGER="app/src/main/java/com/example/fa_ksiegowy/AdsManager.kt"
LAYOUT_PRO="app/src/main/res/layout/activity_settings_pro.xml"

for f in "$SUB_SERVICE" "$SETTINGS_PRO" "$ADS_MANAGER" "$LAYOUT_PRO" \
         "app/src/main/res/values/strings.xml" \
         "app/src/main/res/values-ru/strings.xml" \
         "app/src/main/res/values-pl/strings.xml"; do
  if [ ! -f "$f" ]; then
    echo "BLAD: nie widze $f"
    exit 1
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done
echo "Kopia zapasowa: $BACKUP_DIR/"
echo ""

echo "-> krok 1/4: $SUB_SERVICE (PlanInfo + amountMicros/currencyCode)"
cat > "$SUB_SERVICE" << 'FILEEOF'
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
FILEEOF

echo "-> krok 2/4: $SETTINGS_PRO (dynamiczny odpowiednik ceny miesiecznej)"
cat > "$SETTINGS_PRO" << 'FILEEOF'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.graphics.Color
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * Ekran "Wersja Pro" — pelnoekranowy paywall subskrypcji (miesiac/rok) przez
 * Google Play Billing, z 7-dniowym okresem probnym. Zastepuje dawne okno
 * dialogowe potwierdzenia zakupu — caly przeplyw miesci sie teraz na jednym
 * ekranie zgodnie z referencyjnym projektem.
 */
class SettingsProActivity : BaseActivity() {

    /** Aktualnie wybrany plan w karcie wyboru — domyslnie roczny (najlepsza oferta). */
    private var selectedProductId: String = BillingManager.PRO_YEARLY_PRODUCT_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_pro)
        findViewById<View>(R.id.iv_back).setOnClickListener { finish() }
        setupHeader()
        setupProSection()
    }

    private fun setupHeader() {
        val tvHeader = findViewById<TextView>(R.id.tv_paywall_header)
        val white = getString(R.string.paywall_header_white)
        val blue = getString(R.string.paywall_header_blue)
        val full = "$white $blue"
        val spannable = SpannableStringBuilder(full)
        spannable.setSpan(
            ForegroundColorSpan(Color.WHITE),
            0, white.length,
            SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        spannable.setSpan(
            ForegroundColorSpan(getColorCompat(R.color.accent_blue_light)),
            white.length + 1, full.length,
            SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        tvHeader.text = spannable
        applyStoreSpecificFooter()
    }

    /**
     * Текст "Отмена в любой момент в ..." должен называть тот магазин, через который
     * реально пройдёт подписка (Google Play или Galaxy Store) — а не быть жёстко
     * зашитым на Google Play, как раньше. Если магазин не определён (тестовая
     * установка через Termux/adb, Test Store) — оставляем нейтральный текст без
     * названия магазина.
     */
    private fun applyStoreSpecificFooter() {
        val tvFooter = findViewById<TextView>(R.id.tv_footer_cancel_anytime)
        val storeNameRes = when (SubscriptionService.detectedStore) {
            StoreSource.GOOGLE_PLAY -> R.string.store_name_google_play
            StoreSource.GALAXY_STORE -> R.string.store_name_galaxy_store
            StoreSource.OTHER -> null
        }
        tvFooter.text = if (storeNameRes != null) {
            getString(R.string.paywall_footer_1_store, getString(storeNameRes))
        } else {
            getString(R.string.paywall_footer_1)
        }
    }

    private fun getColorCompat(colorRes: Int): Int =
        androidx.core.content.ContextCompat.getColor(this, colorRes)

    /**
     * Считает реальный эквивалент "в месяц" для годового плана из ЦЕНЫ, которую фактически
     * покажет магазин (amountMicros/currencyCode из RevenueCat) — она уже включает локальный
     * налог (VAT/GST и т.п.), который Google Play/Galaxy Store добавляют поверх цены,
     * заданной в консоли. Раньше это число было зашито строкой (8,33 zł) и не совпадало
     * с реальной ценой после налога — см. Update-67.
     */
    private fun formatMonthlyEquivalent(yearly: SubscriptionService.PlanInfo): String? {
        val yearlyAmount = yearly.amountMicros / 1_000_000.0
        if (yearlyAmount <= 0.0) return null
        val monthlyAmount = yearlyAmount / 12.0
        return try {
            val currency = Currency.getInstance(yearly.currencyCode)
            val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault())
            formatter.currency = currency
            formatter.format(monthlyAmount)
        } catch (e: Exception) {
            null
        }
    }

    /** Временный диагностический диалог — показывает ПОЛНЫЙ текст ошибки RevenueCat
     * (тост обрезает длинные сообщения, а нам важна именно underlyingErrorMessage). */
    private fun showFullError(title: String, message: String) {
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton("OK", null)
            .show()
    }

    private fun refreshUi() {
        val tvStatus = findViewById<TextView>(R.id.tv_pro_status)
        val cardYearly = findViewById<FrameLayout>(R.id.card_yearly)
        val cardMonthly = findViewById<FrameLayout>(R.id.card_monthly)
        val btnCta = findViewById<FrameLayout>(R.id.btn_cta)
        val tvCta = findViewById<TextView>(R.id.tv_cta)

        if (BillingManager.isPro(this)) {
            tvStatus.text = getString(R.string.pro_status_active)
            tvStatus.visibility = View.VISIBLE
            cardYearly.isEnabled = false
            cardMonthly.isEnabled = false
            cardYearly.alpha = 0.5f
            cardMonthly.alpha = 0.5f
            btnCta.isEnabled = false
            btnCta.alpha = 0.5f
            tvCta.text = getString(R.string.pro_status_active)
        } else {
            tvStatus.visibility = View.GONE
            cardYearly.isEnabled = true
            cardMonthly.isEnabled = true
            cardYearly.alpha = 1f
            cardMonthly.alpha = 1f
            btnCta.isEnabled = true
            btnCta.alpha = 1f
            tvCta.text = getString(R.string.paywall_cta)
            applySelectionState()
        }
    }

    private fun applySelectionState() {
        val cardYearly = findViewById<FrameLayout>(R.id.card_yearly)
        val cardMonthly = findViewById<FrameLayout>(R.id.card_monthly)
        val radioYearly = findViewById<ImageView>(R.id.radio_yearly)
        val radioMonthly = findViewById<ImageView>(R.id.radio_monthly)

        val yearlySelected = selectedProductId == BillingManager.PRO_YEARLY_PRODUCT_ID
        cardYearly.setBackgroundResource(if (yearlySelected) R.drawable.card_plan_selected else R.drawable.card_plan_unselected)
        cardMonthly.setBackgroundResource(if (!yearlySelected) R.drawable.card_plan_selected else R.drawable.card_plan_unselected)
        radioYearly.setImageResource(if (yearlySelected) R.drawable.ic_radio_selected else R.drawable.ic_radio_unselected)
        radioMonthly.setImageResource(if (!yearlySelected) R.drawable.ic_radio_selected else R.drawable.ic_radio_unselected)
    }

    private fun setupProSection() {
        val tvPriceYearly = findViewById<TextView>(R.id.tv_price_yearly)
        val tvPriceMonthly = findViewById<TextView>(R.id.tv_price_monthly)
        val tvTrialYearly = findViewById<TextView>(R.id.tv_trial_yearly)
        val tvTrialMonthly = findViewById<TextView>(R.id.tv_trial_monthly)
        val tvPerMonthNote = findViewById<TextView>(R.id.tv_per_month_note)

        // Domyslne ceny (te same co w prawdziwej konfiguracji Google Play) — widoczne
        // od razu, zanim doczyta sie prawdziwa cena z Billing.
        tvTrialYearly.text = getString(R.string.paywall_trial_yearly, getString(R.string.paywall_price_yearly_default))
        tvTrialMonthly.text = getString(R.string.paywall_trial_monthly, getString(R.string.paywall_price_monthly_default))
        tvPerMonthNote.text = getString(R.string.paywall_per_month_note, getString(R.string.paywall_price_monthly_equivalent_default))

        refreshUi()

        BillingManager.connect(this) { connected, errorMessage ->
            runOnUiThread {
                if (!connected) {
                    // Временная диагностика: показываем точную причину, почему RevenueCat не отдал
                    // оффер/пакеты — это нужно, чтобы понять, что поправить в Dashboard.
                    if (errorMessage != null) {
                        showFullError("RC offerings error", errorMessage)
                    }
                    return@runOnUiThread
                }
                BillingManager.restorePurchases(this) { refreshUi() }
                if (!BillingManager.isPro(this)) {
                    BillingManager.querySubscriptionPlans { monthly, yearly, plansError ->
                        runOnUiThread {
                            if (yearly != null) {
                                tvPriceYearly.text = yearly.price
                                tvTrialYearly.text = getString(R.string.paywall_trial_yearly, yearly.price)
                                formatMonthlyEquivalent(yearly)?.let { equivalent ->
                                    tvPerMonthNote.text = getString(R.string.paywall_per_month_note, equivalent)
                                }
                            }
                            if (monthly != null) {
                                tvPriceMonthly.text = monthly.price
                                tvTrialMonthly.text = getString(R.string.paywall_trial_monthly, monthly.price)
                            }
                            if (plansError != null) {
                                showFullError("RC plans error", plansError)
                            }
                        }
                    }
                }
            }
        }

        findViewById<FrameLayout>(R.id.card_yearly).setOnClickListener {
            selectedProductId = BillingManager.PRO_YEARLY_PRODUCT_ID
            applySelectionState()
        }
        findViewById<FrameLayout>(R.id.card_monthly).setOnClickListener {
            selectedProductId = BillingManager.PRO_MONTHLY_PRODUCT_ID
            applySelectionState()
        }
        findViewById<FrameLayout>(R.id.btn_cta).setOnClickListener {
            if (!BillingManager.isPro(this)) {
                val btnCta = findViewById<FrameLayout>(R.id.btn_cta)
                btnCta.isEnabled = false
                BillingManager.launchPurchase(this, selectedProductId) { success, errorMessage, userCancelled ->
                    runOnUiThread {
                        btnCta.isEnabled = true
                        if (success) {
                            refreshUi()
                            if (errorMessage != null) {
                                // Диагностика: покупка прошла, но isPro всё ещё false — показываем,
                                // какие entitlements реально пришли от RevenueCat, чтобы свериться
                                // с ENTITLEMENT_ID в SubscriptionService.kt.
                                showFullError("Purchase succeeded — entitlement mismatch?", errorMessage)
                            }
                        } else if (!userCancelled && errorMessage != null) {
                            // Не показываем диалог при обычной отмене пользователем — только при реальной ошибке.
                            showFullError("Purchase error", errorMessage)
                        }
                    }
                }
            }
        }

        findViewById<TextView>(R.id.tv_restore_purchases).setOnClickListener {
            BillingManager.restorePurchases(this) { isPro ->
                runOnUiThread {
                    refreshUi()
                    val messageRes = if (isPro) R.string.paywall_restore_success else R.string.paywall_restore_nothing_found
                    Toast.makeText(this, getString(messageRes), Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Na wypadek powrotu z okna oplaty Google Play — odswiez status i wyglad ekranu.
        BillingManager.restorePurchases(this) { refreshUi() }
    }
}
FILEEOF

echo "-> krok 3/4: $ADS_MANAGER (test-device fix dla banera w release .aab)"
cat > "$ADS_MANAGER" << 'FILEEOF'
package com.example.fa_ksiegowy

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.RequestConfiguration
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform

/**
 * Показ баннера только для пользователей без Pro.
 *
 * AdView создаётся программно (а не через XML-тег) и добавляется в
 * пустой FrameLayout-контейнер из разметки. Это осознанное решение: при
 * инфлейте `<com.google.android.gms.ads.AdView>` напрямую из XML без
 * атрибута adSize текущая версия Google Mobile Ads SDK показывает вместо
 * рекламы ошибку "Required XML attribute "adSize" was missing." —
 * потому что setAdSize()/adUnitId() в коде вызываются уже ПОСЛЕ инфлейта,
 * а SDK ожидает их либо в XML, либо до первого добавления View в иерархию.
 * Создание AdView(activity) в коде и его addView() в контейнер полностью
 * убирает эту гонку и является официально рекомендуемым способом.
 *
 * Диагностика (для отладки показа рекламы): каждый шаг пишет свой статус в
 * debugView — маленькую серую строку под баннером. Работает ТОЛЬКО в debug-
 * сборке (проверка applicationInfo.FLAG_DEBUGGABLE) — в релизной сборке,
 * которая уходит в Google Play/Galaxy Store, ни Log.i, ни текст в debugView
 * не пишутся, так что диагностический вывод не может попасть на экран
 * обычного пользователя или в системный logcat.
 */
object AdsManager {

    private var sdkInitialized = false
    private const val TEST_BANNER_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"
    private const val PROD_BANNER_UNIT_ID = "ca-app-pub-9218963926031039/9552844934"

    // ВАЖНО (fix Update-67): в релизной сборке (.aab) isDebuggable=false, поэтому баннер
    // всегда грузится через БОЕВОЙ PROD_BANNER_UNIT_ID — даже на вашем устройстве,
    // добавленном как тестовое в AdMob Dashboard. Без явного setTestDeviceIds() ниже SDK
    // на устройстве об этом "тестовом" статусе ничего не знает, и для совсем нового
    // боевого рекламного блока Google может первое время не отдавать заполнение (No Fill) —
    // баннер будет выглядеть как "пропавший". Добавьте сюда хэшированный Device ID из
    // logcat (adb logcat | grep -i "Ads" — там будет строка вида "Use RequestConfiguration.
    // Builder...setTestDeviceIds(Arrays.asList("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"))"), чтобы
    // запросы с этого устройства ГАРАНТИРОВАННО помечались как тестовые даже на боевом
    // ad unit ID — это не влияет на реальных пользователей.
    private val TEST_DEVICE_IDS = listOf<String>(
        // "ВАШ_ХЭШИРОВАННЫЙ_DEVICE_ID_ИЗ_LOGCAT"
    )

    private fun isDebuggable(context: android.content.Context): Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun setDebugStatus(context: android.content.Context, debugView: TextView?, text: String) {
        if (!isDebuggable(context)) return
        Log.i("AdsManager", "STATUS: $text")
        debugView?.text = "Ad status: $text"
    }

    /**
     * Создаёт AdView программно, кладёт его в [container] и запускает загрузку.
     * Возвращает созданный AdView — вызывающая Activity должна сохранить его
     * (например, в поле класса), чтобы вызвать destroy()/pause() в своём
     * жизненном цикле.
     */
    fun setupAndLoadBanner(activity: Activity, container: ViewGroup, debugView: TextView? = null): AdView {
        val adView = AdView(activity)
        container.removeAllViews()
        container.addView(adView)

        if (BillingManager.isPro(activity)) {
            container.visibility = View.GONE
            setDebugStatus(activity, debugView, "hidden (Pro active)")
            return adView
        }

        setDebugStatus(activity, debugView, "starting…")

        try {
            adView.setAdSize(AdSize.BANNER)

            val isDebuggable = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            adView.adUnitId = if (isDebuggable) TEST_BANNER_UNIT_ID else PROD_BANNER_UNIT_ID
            setDebugStatus(activity, debugView, "isDebuggable=$isDebuggable, unit=${adView.adUnitId}")

            if (isDebuggable) {
                // Тестовый блок Google не требует согласия пользователя —
                // грузим его сразу, без UMP.
                initAndLoad(activity, container, adView, debugView)
                return adView
            }

            val consentInformation = UserMessagingPlatform.getConsentInformation(activity)
            val params = ConsentRequestParameters.Builder().build()

            consentInformation.requestConsentInfoUpdate(
                activity,
                params,
                {
                    UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { formError ->
                        if (formError != null) {
                            setDebugStatus(activity, debugView, "consent form error: ${formError.message}")
                        }
                        if (consentInformation.canRequestAds()) {
                            initAndLoad(activity, container, adView, debugView)
                        } else {
                            setDebugStatus(activity, debugView, "blocked — canRequestAds()=false (нужно опубликовать Privacy & messaging в AdMob)")
                        }
                    }
                },
                { requestError ->
                    setDebugStatus(activity, debugView, "consent info update error: ${requestError.message}")
                }
            )

            if (consentInformation.canRequestAds() && !sdkInitialized) {
                initAndLoad(activity, container, adView, debugView)
            }
        } catch (e: Exception) {
            // Ловим вообще любое исключение на этом пути, чтобы оно не терялось молча —
            // выводим текст ошибки прямо на экран.
            setDebugStatus(activity, debugView, "EXCEPTION: ${e.javaClass.simpleName}: ${e.message}")
        }

        return adView
    }

    private fun initAndLoad(activity: Activity, container: ViewGroup, adView: AdView, debugView: TextView?) {
        setDebugStatus(activity, debugView, "initializing SDK…")
        if (!sdkInitialized) {
            sdkInitialized = true
            if (TEST_DEVICE_IDS.isNotEmpty()) {
                MobileAds.setRequestConfiguration(
                    RequestConfiguration.Builder().setTestDeviceIds(TEST_DEVICE_IDS).build()
                )
            }
            MobileAds.initialize(activity) {
                setDebugStatus(activity, debugView, "SDK initialized, loading ad…")
            }
        }
        container.visibility = View.VISIBLE
        adView.adListener = object : AdListener() {
            override fun onAdLoaded() {
                setDebugStatus(activity, debugView, "loaded OK ✅")
            }
            override fun onAdFailedToLoad(error: LoadAdError) {
                // errorCode 3 = ERROR_CODE_NO_FILL — самая частая причина для новых
                // рекламных блоков: у Google пока нет рекламы для показа именно вам.
                setDebugStatus(activity, debugView, "FAILED code=${error.code} domain=${error.domain} msg=${error.message}")
            }
        }
        setDebugStatus(activity, debugView, "loadAd() called…")
        adView.loadAd(AdRequest.Builder().build())
    }

    /** Вызывать сразу после успешной покупки Pro, чтобы мгновенно убрать баннер без перезапуска экрана. */
    fun hideBanner(container: ViewGroup, adView: AdView) {
        container.visibility = View.GONE
        adView.pause()
    }
}
FILEEOF

echo "-> krok 4/4: layout (id tv_per_month_note) + strings.xml (en/ru/pl)"
python3 << 'PYEOF_STRINGS'
def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old in candidates:
        if content.count(old) == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    raise SystemExit(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")

LAYOUT = "app/src/main/res/layout/activity_settings_pro.xml"
str_replace_any(
    LAYOUT,
    ['                    <TextView\n'
     '                        android:layout_width="wrap_content" android:layout_height="wrap_content"\n'
     '                        android:layout_marginStart="6dp" android:text="@string/paywall_per_month_note"\n'
     '                        android:textColor="@color/accent_blue_light" android:textSize="13sp"/>'],
    '                    <TextView android:id="@+id/tv_per_month_note"\n'
    '                        android:layout_width="wrap_content" android:layout_height="wrap_content"\n'
    '                        android:layout_marginStart="6dp" android:text="@string/paywall_per_month_note"\n'
    '                        android:textColor="@color/accent_blue_light" android:textSize="13sp"/>',
    "tv_per_month_note id"
)

LOCALES = {
    "app/src/main/res/values/strings.xml": {
        "old": '    <string name="paywall_per_month_note">Only 8.33 zł / month</string>',
        "new": ('    <string name="paywall_per_month_note">Only %1$s / month</string>\n'
                '    <string name="paywall_price_monthly_equivalent_default">8.33 zł</string>'),
    },
    "app/src/main/res/values-ru/strings.xml": {
        "old": '    <string name="paywall_per_month_note">Всего 8,33 zł / месяц</string>',
        "new": ('    <string name="paywall_per_month_note">Всего %1$s / месяц</string>\n'
                '    <string name="paywall_price_monthly_equivalent_default">8,33 zł</string>'),
    },
    "app/src/main/res/values-pl/strings.xml": {
        "old": '    <string name="paywall_per_month_note">Tylko 8,33 zł / miesiąc</string>',
        "new": ('    <string name="paywall_per_month_note">Tylko %1$s / miesiąc</string>\n'
                '    <string name="paywall_price_monthly_equivalent_default">8,33 zł</string>'),
    },
}
for path, spec in LOCALES.items():
    str_replace_any(path, [spec["old"]], spec["new"], "paywall_per_month_note template + default equivalent")

print("")
print("Wszystkie patche (strings/layout) zastosowane pomyslnie.")
PYEOF_STRINGS

echo ""
echo "=== Update 67 zastosowany ==="
echo "1) Plakietka 'X / miesiac' pod planem rocznym liczy sie teraz z realnej ceny"
echo "   (z podatkiem) zwroconej przez RevenueCat, zamiast bylo zaszyte na sztywno."
echo "2) AdsManager.kt ma teraz miejsce na TEST_DEVICE_IDS — wpisz tam swoj"
echo "   zahaszowany Device ID z logcat (adb logcat | grep -i \"Ads\"), zeby"
echo "   baner AdMob dzialal pewnie takze w release .aab na Twoim urzadzeniu."
echo ""
echo "Dalej: podbij versionCode/versionName (jesli robisz to recznie), zbuduj:"
echo "  ./gradlew bundleRelease"
echo "i wgraj .aab do Google Play Console -> Inner/Closed testing -> Create new release."
