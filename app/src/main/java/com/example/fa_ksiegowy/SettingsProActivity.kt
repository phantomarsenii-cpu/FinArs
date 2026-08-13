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
