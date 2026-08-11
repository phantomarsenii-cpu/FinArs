package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.widget.Button
import android.widget.TextView

/** Разблокировка Pro-версии (разовая покупка через Google Play Billing). */
class SettingsProActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_pro)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        setupProSection()
    }

    private fun setupProSection() {
        val tvStatus = findViewById<TextView>(R.id.tv_pro_status)
        val btnUnlock = findViewById<Button>(R.id.btn_unlock_pro)

        fun refreshUi() {
            if (BillingManager.isPro(this)) {
                tvStatus.text = getString(R.string.pro_status_active)
                btnUnlock.isEnabled = false
                btnUnlock.text = getString(R.string.pro_status_active)
            } else {
                tvStatus.text = getString(R.string.pro_status_locked)
                btnUnlock.isEnabled = true
            }
        }
        refreshUi()

        BillingManager.connect(this) { connected ->
            runOnUiThread {
                if (!connected) return@runOnUiThread
                BillingManager.restorePurchases(this) { refreshUi() }
                if (!BillingManager.isPro(this)) {
                    BillingManager.queryProProductDetails { price ->
                        runOnUiThread {
                            btnUnlock.text = if (price != null) {
                                getString(R.string.pro_unlock_button_price, price)
                            } else {
                                getString(R.string.pro_unlock_button)
                            }
                        }
                    }
                }
            }
        }

        btnUnlock.setOnClickListener {
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.pro_info_title))
                .setMessage(getString(R.string.pro_info_message))
                .setPositiveButton(getString(R.string.pro_info_continue)) { _, _ ->
                    BillingManager.launchPurchase(this)
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }
    }

    override fun onResume() {
        super.onResume()
        // На случай возврата из окна оплаты Google Play — обновить статус и кнопку.
        BillingManager.restorePurchases(this) {
            val tvStatus = findViewById<TextView>(R.id.tv_pro_status)
            val btnUnlock = findViewById<Button>(R.id.btn_unlock_pro)
            if (BillingManager.isPro(this)) {
                tvStatus.text = getString(R.string.pro_status_active)
                btnUnlock.isEnabled = false
                btnUnlock.text = getString(R.string.pro_status_active)
            }
        }
    }
}
