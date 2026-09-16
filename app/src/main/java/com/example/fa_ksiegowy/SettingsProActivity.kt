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

    // Real currency codes from RevenueCat, filled in once querySubscriptionPlans
    // returns. Null until then, so the CTA/trial "0" text falls back to the
    // hardcoded Polish default (see updateZeroPriceTexts()).
    private var yearlyCurrencyCode: String? = null
    private var monthlyCurrencyCode: String? = null

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
     * "0" in whichever currency the currently SELECTED plan actually charges
     * in (e.g. "0 zł" for PLN, "$0" for USD) — not a value hardcoded into the
     * string resources, which used to always say "0 zł" even for buyers
     * outside Poland. Falls back to "0 zł" while the real currency hasn't
     * loaded from RevenueCat yet.
     */
    private fun zeroPriceText(): String {
        val currencyCode = if (selectedProductId == BillingManager.PRO_YEARLY_PRODUCT_ID) {
            yearlyCurrencyCode
        } else {
            monthlyCurrencyCode
        }
        return PriceFormatter.zero(currencyCode, fallback = getString(R.string.paywall_price_zero_default))
    }

    /** Refreshes every piece of copy that embeds the "0 <currency>" trial text
     *  for the currently selected plan — call after the selection changes or
     *  once real currency codes arrive from RevenueCat. */
    private fun updateZeroPriceTexts() {
        if (!BillingManager.isPro(this)) {
            findViewById<TextView>(R.id.tv_cta).text = getString(R.string.paywall_cta, zeroPriceText())
        }
        val yearlyZero = PriceFormatter.zero(yearlyCurrencyCode, fallback = getString(R.string.paywall_price_zero_default))
        val monthlyZero = PriceFormatter.zero(monthlyCurrencyCode, fallback = getString(R.string.paywall_price_zero_default))
        val yearlyPrice = currentYearlyPriceText ?: getString(R.string.paywall_price_yearly_default)
        val monthlyPrice = currentMonthlyPriceText ?: getString(R.string.paywall_price_monthly_default)
        findViewById<TextView>(R.id.tv_trial_yearly).text =
            getString(R.string.paywall_trial_yearly, yearlyPrice, yearlyZero)
        findViewById<TextView>(R.id.tv_trial_monthly).text =
            getString(R.string.paywall_trial_monthly, monthlyPrice, monthlyZero)
    }

    // Last real (or default) price strings shown for each plan, kept so
    // updateZeroPriceTexts() can rebuild the trial sentence without needing
    // a fresh RevenueCat round trip.
    private var currentYearlyPriceText: String? = null
    private var currentMonthlyPriceText: String? = null

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
        val monthlyMicros = (yearly.amountMicros / 12.0).toLong()
        // Old fallback (Locale.getDefault()) kept only for currencies
        // PriceFormatter doesn't know about, so nothing breaks for those.
        val legacyFallback = try {
            val currency = Currency.getInstance(yearly.currencyCode)
            NumberFormat.getCurrencyInstance(Locale.getDefault()).apply { this.currency = currency }
                .format(monthlyMicros / 1_000_000.0)
        } catch (e: Exception) {
            return null
        }
        // PriceFormatter resolves the symbol from the currency's OWN home
        // locale (e.g. PLN -> pl_PL), not Locale.getDefault() — the device's
        // UI language. That matters because Java falls back to the raw ISO
        // code ("PLN") whenever the running locale has no localized symbol
        // for that currency, e.g. a PLN price on a Russian-language device.
        return PriceFormatter.format(
            amountMicros = monthlyMicros,
            currencyCode = yearly.currencyCode,
            fallback = legacyFallback
        )
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
            tvCta.text = getString(R.string.paywall_cta, zeroPriceText())
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
        updateZeroPriceTexts()
    }

    private fun setupProSection() {
        val tvPriceYearly = findViewById<TextView>(R.id.tv_price_yearly)
        val tvPriceMonthly = findViewById<TextView>(R.id.tv_price_monthly)
        val tvTrialYearly = findViewById<TextView>(R.id.tv_trial_yearly)
        val tvTrialMonthly = findViewById<TextView>(R.id.tv_trial_monthly)
        val tvPerMonthNote = findViewById<TextView>(R.id.tv_per_month_note)

        // Domyslne ceny (te same co w prawdziwej konfiguracji Google Play) — widoczne
        // od razu, zanim doczyta sie prawdziwa cena z Billing.
        currentYearlyPriceText = getString(R.string.paywall_price_yearly_default)
        currentMonthlyPriceText = getString(R.string.paywall_price_monthly_default)
        tvPerMonthNote.text = getString(R.string.paywall_per_month_note, getString(R.string.paywall_price_monthly_equivalent_default))

        refreshUi()
        updateZeroPriceTexts()

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
                                // Reformat with the currency's own home-locale
                                // symbol (falls back to RevenueCat's own
                                // .formatted string for currencies we don't
                                // recognize) — see PriceFormatter for why.
                                val yearlyPriceText = PriceFormatter.format(
                                    amountMicros = yearly.amountMicros,
                                    currencyCode = yearly.currencyCode,
                                    fallback = yearly.price
                                )
                                tvPriceYearly.text = yearlyPriceText
                                currentYearlyPriceText = yearlyPriceText
                                yearlyCurrencyCode = yearly.currencyCode
                                formatMonthlyEquivalent(yearly)?.let { equivalent ->
                                    tvPerMonthNote.text = getString(R.string.paywall_per_month_note, equivalent)
                                }
                            }
                            if (monthly != null) {
                                val monthlyPriceText = PriceFormatter.format(
                                    amountMicros = monthly.amountMicros,
                                    currencyCode = monthly.currencyCode,
                                    fallback = monthly.price
                                )
                                tvPriceMonthly.text = monthlyPriceText
                                currentMonthlyPriceText = monthlyPriceText
                                monthlyCurrencyCode = monthly.currencyCode
                            }
                            updateZeroPriceTexts()
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
