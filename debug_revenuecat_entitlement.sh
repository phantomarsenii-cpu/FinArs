#!/data/data/com.termux/files/usr/bin/bash
# FinArs — debug_revenuecat_entitlement.sh
# Покупка (симуляция успеха в Test Store) проходит, но isPro не активируется —
# добавляем диагностику: после успешной покупки показываем, какие entitlements
# реально пришли от RevenueCat (Active / All), чтобы свериться с ENTITLEMENT_ID.
# Меняет ТОЛЬКО SubscriptionService.kt и SettingsProActivity.kt.
set -euo pipefail

echo "=== FinArs: диагностика entitlement RevenueCat ==="

REPO_ROOT="$HOME/FA_ksiegowy"
cd "$REPO_ROOT"

TS=$(date +%Y%m%d_%H%M%S)
PKG_DIR="app/src/main/java/com/example/fa_ksiegowy"

if [ ! -d "$PKG_DIR" ]; then
    echo "ERROR: $PKG_DIR не найден. Запустите из корня репозитория."
    exit 1
fi

echo "--- Backing up files ---"
[ -f "$PKG_DIR/SubscriptionService.kt" ] && cp "$PKG_DIR/SubscriptionService.kt" "$PKG_DIR/SubscriptionService.kt.bak_${TS}" || true
[ -f "$PKG_DIR/SettingsProActivity.kt" ] && cp "$PKG_DIR/SettingsProActivity.kt" "$PKG_DIR/SettingsProActivity.kt.bak_${TS}" || true

echo "Writing $PKG_DIR/SubscriptionService.kt"
cat > "$PKG_DIR/SubscriptionService.kt" << 'FINARS_EOF'
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

    // TODO: вставить боевые публичные ключи после того, как протестируете покупки через
    // Test Store (RevenueCat Dashboard -> Project settings -> API keys). У каждого магазина
    // СВОЙ отдельный публичный ключ (goog_XXXXX для Google Play, galx_XXXXX для Galaxy Store).
    // Пока они пустые — сервис использует Test Store всегда, независимо от того, откуда
    // реально установлено приложение (см. buildConfiguration()).
    private const val GOOGLE_PLAY_API_KEY = "" // напр. "goog_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    private const val GALAXY_STORE_API_KEY = "" // напр. "galx_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

    // Пока идёт тестирование на Galaxy-устройстве через боевой ключ (после того как он появится),
    // GalaxyBillingMode.TEST позволяет проверить покупку без реального списания денег.
    // ВАЖНО: перед сборкой релиза для Galaxy Store — переключить на GalaxyBillingMode.PRODUCTION.
    private val GALAXY_BILLING_MODE_FOR_TESTING = GalaxyBillingMode.TEST

    /**
     * Идентификатор Entitlement в RevenueCat Dashboard, дающий доступ ко всем Pro-функциям
     * приложения (единый доступ и для месячной, и для годовой подписки).
     * TODO: сверить точное название с RevenueCat Dashboard -> Entitlements (сейчас "premium").
     */
    const val ENTITLEMENT_ID = "premium"

    private const val OFFERING_ID = "default"

    // Идентификаторы пакетов внутри Offering "default" — стандартные RevenueCat-пакеты
    // (видны в Dashboard как "$rc_monthly" / "$rc_yearly", см. Update-40 offering).
    const val PACKAGE_MONTHLY = "\$rc_monthly"
    const val PACKAGE_YEARLY = "\$rc_annual"

    private const val PREFS_NAME = "settings"
    private const val KEY_IS_PRO_RC = "isProRevenueCat"

    data class PlanInfo(val price: String, val trialDays: Int?)

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
        return PlanInfo(product.price.formatted, trialDays)
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
FINARS_EOF

echo "Writing $PKG_DIR/SettingsProActivity.kt"
cat > "$PKG_DIR/SettingsProActivity.kt" << 'FINARS_EOF'
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

        // Domyslne ceny (te same co w prawdziwej konfiguracji Google Play) — widoczne
        // od razu, zanim doczyta sie prawdziwa cena z Billing.
        tvTrialYearly.text = getString(R.string.paywall_trial_yearly, getString(R.string.paywall_price_yearly_default))
        tvTrialMonthly.text = getString(R.string.paywall_trial_monthly, getString(R.string.paywall_price_monthly_default))

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
FINARS_EOF


echo ""
echo "--- Проверка баланса скобок ---"
CHECK_FAILED=0
for f in SubscriptionService.kt SettingsProActivity.kt; do
    if python3 - "$PKG_DIR/$f" << 'PYCHECK_EOF'
import sys
path = sys.argv[1]
s = open(path, encoding="utf-8").read()
stack = []
pairs = {')': '(', ']': '[', '}': '{'}
in_string = False
str_char = ''
i = 0
line = 1
while i < len(s):
    c = s[i]
    if c == '\n':
        line += 1
    if in_string:
        if c == '\\\\':
            i += 2
            continue
        if c == str_char:
            in_string = False
        i += 1
        continue
    if c in ('"', "'"):
        in_string = True
        str_char = c
        i += 1
        continue
    if c == '/' and i + 1 < len(s) and s[i + 1] == '/':
        j = s.find('\n', i)
        i = j if j != -1 else len(s)
        continue
    if c in '([{':
        stack.append((c, line))
    elif c in ')]}':
        if not stack or pairs[c] != stack[-1][0]:
            print(f"{path}: MISMATCH at line {line}")
            sys.exit(1)
        stack.pop()
    i += 1
if stack:
    print(f"{path}: UNCLOSED {stack}")
    sys.exit(1)
print(f"{path}: OK")
PYCHECK_EOF
    then
        :
    else
        CHECK_FAILED=1
    fi
done
if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "ERROR: синтаксическая проблема — остановка без коммита."
    exit 1
fi

echo ""
echo "--- git add / commit / push ---"
git add "$PKG_DIR/SubscriptionService.kt" "$PKG_DIR/SettingsProActivity.kt"
if git diff --cached --quiet; then
    echo "Нет изменений для коммита."
else
    git commit -m "Add entitlement diagnostics after purchase success"
    git push origin main
    echo ""
    echo "Готово. Пуш выполнен — сборка APK запустится в GitHub Actions."
fi
