package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.widget.Button
import android.widget.TextView

/** Разблокировка Pro-версии — подписка (месяц/год) через Google Play Billing, с 7-дневным пробным периодом. */
class SettingsProActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_pro)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        setupProSection()
    }

    private fun refreshUi() {
        val tvStatus = findViewById<TextView>(R.id.tv_pro_status)
        val tvTrialHint = findViewById<TextView>(R.id.tv_pro_trial_hint)
        val btnMonthly = findViewById<Button>(R.id.btn_plan_monthly)
        val btnYearly = findViewById<Button>(R.id.btn_plan_yearly)

        if (BillingManager.isPro(this)) {
            tvStatus.text = getString(R.string.pro_status_active)
            tvTrialHint.visibility = android.view.View.GONE
            btnMonthly.isEnabled = false
            btnYearly.isEnabled = false
            btnMonthly.text = getString(R.string.pro_status_active)
            btnYearly.visibility = android.view.View.GONE
        } else {
            tvStatus.text = getString(R.string.pro_status_locked)
            tvTrialHint.visibility = android.view.View.VISIBLE
            btnMonthly.isEnabled = true
            btnYearly.isEnabled = true
            btnYearly.visibility = android.view.View.VISIBLE
        }
    }

    private fun setupProSection() {
        refreshUi()

        BillingManager.connect(this) { connected ->
            runOnUiThread {
                if (!connected) return@runOnUiThread
                BillingManager.restorePurchases(this) { refreshUi() }
                if (!BillingManager.isPro(this)) {
                    BillingManager.querySubscriptionPlans { monthly, yearly ->
                        runOnUiThread {
                            val btnMonthly = findViewById<Button>(R.id.btn_plan_monthly)
                            val btnYearly = findViewById<Button>(R.id.btn_plan_yearly)
                            btnMonthly.text = if (monthly != null) {
                                getString(R.string.pro_plan_monthly_price, monthly.price)
                            } else getString(R.string.pro_plan_monthly)
                            btnYearly.text = if (yearly != null) {
                                getString(R.string.pro_plan_yearly_price, yearly.price)
                            } else getString(R.string.pro_plan_yearly)
                        }
                    }
                }
            }
        }

        findViewById<Button>(R.id.btn_plan_monthly).setOnClickListener {
            confirmAndLaunch(BillingManager.PRO_MONTHLY_PRODUCT_ID)
        }
        findViewById<Button>(R.id.btn_plan_yearly).setOnClickListener {
            confirmAndLaunch(BillingManager.PRO_YEARLY_PRODUCT_ID)
        }
    }

    private fun confirmAndLaunch(productId: String) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.pro_info_title))
            .setMessage(getString(R.string.pro_info_message))
            .setPositiveButton(getString(R.string.pro_info_continue)) { _, _ ->
                BillingManager.launchPurchase(this, productId)
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    override fun onResume() {
        super.onResume()
        // На случай возврата из окна оплаты Google Play — обновить статус и кнопки.
        BillingManager.restorePurchases(this) { refreshUi() }
    }
}
