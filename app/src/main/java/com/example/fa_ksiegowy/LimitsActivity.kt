package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Pelnoekranowy widok "Limity" — dokladnie wedlug makietu (2 karty limitow +
 * karta informacyjna "O limitach"). Otwierany z karty Limitow na ekranie
 * glownym (MainActivity / MineFragment).
 */
class LimitsActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_limits)
        BottomNavBar.attach(this, BottomNavBar.Tab.START)

        findViewById<ImageView>(R.id.iv_back).setOnClickListener { finish() }

        loadLimits()
    }

    override fun onResume() {
        super.onResume()
        loadLimits()
    }

    private fun loadLimits() {
        lifecycleScope.launch {
            val limits = LimitsHelper.compute(this@LimitsActivity)

            findViewById<TextView>(R.id.tv_monthly_percent).text =
                "${limits.monthly.percent.coerceAtMost(100)}%"
            findViewById<TextView>(R.id.tv_monthly_amounts).text =
                "${formatMoney(limits.monthly.current)} zł / ${formatMoney(limits.monthly.limit)} zł"
            findViewById<ProgressBar>(R.id.pb_monthly).progress = limits.monthly.percent.coerceAtMost(100)
            findViewById<TextView>(R.id.tv_monthly_remaining).text =
                getString(R.string.limits_remaining, formatMoney((limits.monthly.limit - limits.monthly.current).coerceAtLeast(0.0)))
            findViewById<TextView>(R.id.tv_monthly_limit).text =
                getString(R.string.limits_limit_of, formatMoney(limits.monthly.limit))

            val stage = limits.bracketStage
            findViewById<TextView>(R.id.tv_bracket_title).text = when (stage.stage) {
                LimitsHelper.BracketStage.TAX_FREE -> getString(R.string.limit_bracket_title_tax_free)
                LimitsHelper.BracketStage.RATE_12 -> getString(R.string.limit_bracket_title_rate12)
                LimitsHelper.BracketStage.RATE_32 -> getString(R.string.limit_bracket_title_rate32)
            }
            findViewById<TextView>(R.id.tv_bracket_percent).text = "${stage.percent.coerceAtMost(100)}%"
            findViewById<TextView>(R.id.tv_bracket_amounts).text =
                "${formatMoney(stage.barCurrent)} zł / ${formatMoney(stage.barLimit)} zł"
            findViewById<ProgressBar>(R.id.pb_bracket).progress = stage.percent
            findViewById<TextView>(R.id.tv_bracket_remaining).text =
                getString(R.string.limits_remaining, formatMoney((stage.barLimit - stage.barCurrent).coerceAtLeast(0.0)))
            findViewById<TextView>(R.id.tv_bracket_limit).text =
                getString(R.string.limits_limit_of, formatMoney(stage.barLimit))
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)
}
