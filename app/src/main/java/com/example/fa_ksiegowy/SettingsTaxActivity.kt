package com.example.fa_ksiegowy

import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast

/**
 * Настройки налогов и формы деятельности:
 *  1) Тип деятельности (niezarejestrowana / JDG: skala, liniowy, ryczałt) —
 *     от него зависит применяемый лимит и то, какая декларация актуальна
 *     (PIT-36 / PIT-36L / PIT-28), см. ActivityTypeHelper.
 *  2) Минимальное вознаграждение (minimalne wynagrodzenie) — базa для
 *     расчёта месячного лимита niezarejestrowanej działalności (75% от неё).
 *  3) Ставка ryczałtu (только если выбран ryczałt) — зависит от PKD,
 *     вводится пользователем вручную.
 *  4) "Прочие доходы" — как и раньше, влияют на то, какая часть прибыли
 *     из приложения облагается по 12%, а какая — по 32% (только для skali).
 *
 * Налог всегда считается автоматически по официальной формуле для выбранной
 * формы (см. TaxHelper) — ручного ввода процента нет.
 */
class SettingsTaxActivity : BaseActivity() {
    private lateinit var prefs: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_tax)
        prefs = getSharedPreferences("settings", MODE_PRIVATE)

        val year = TaxHelper.currentYear()
        findViewById<TextView>(R.id.tv_other_income_label).text =
            getString(R.string.other_income_label, year)

        setupActivityType()
        setupMinWage()

        val etOtherIncome = findViewById<EditText>(R.id.et_other_income)
        etOtherIncome.setText(TaxHelper.getOtherIncome(prefs, year).toString())
        findViewById<Button>(R.id.btn_save_other_income).setOnClickListener {
            val v = etOtherIncome.text.toString().toDoubleOrNull() ?: 0.0
            TaxHelper.setOtherIncome(prefs, year, v)

            val ryczaltRateField = findViewById<EditText>(R.id.et_ryczalt_rate)
            if (ryczaltRateField.visibility == View.VISIBLE) {
                val rate = ryczaltRateField.text.toString().toDoubleOrNull() ?: 0.0
                ActivityTypeHelper.setRyczaltRate(prefs, rate)
            }
            val minWage = findViewById<EditText>(R.id.et_min_wage).text.toString().toDoubleOrNull()
            if (minWage != null && minWage > 0.0) {
                ActivityTypeHelper.setMinWage(prefs, minWage)
                updateMonthlyLimitPreview()
            }

            Toast.makeText(this, getString(R.string.saved), Toast.LENGTH_SHORT).show()
        }
    }

    private fun setupActivityType() {
        val rg = findViewById<RadioGroup>(R.id.rg_activity_type)
        val current = ActivityTypeHelper.get(prefs)
        val idFor = mapOf(
            ActivityType.NIEZAREJESTROWANA to R.id.rb_niezarejestrowana,
            ActivityType.JDG_SKALA to R.id.rb_jdg_skala,
            ActivityType.JDG_LINIOWY to R.id.rb_jdg_liniowy,
            ActivityType.JDG_RYCZALT to R.id.rb_jdg_ryczalt
        )
        rg.check(idFor[current] ?: R.id.rb_niezarejestrowana)
        updateRyczaltFieldVisibility(current)
        val etRate = findViewById<EditText>(R.id.et_ryczalt_rate)
        val savedRate = ActivityTypeHelper.getRyczaltRate(prefs)
        if (savedRate > 0.0) etRate.setText(savedRate.toString())

        rg.setOnCheckedChangeListener { _, checkedId ->
            val type = when (checkedId) {
                R.id.rb_niezarejestrowana -> ActivityType.NIEZAREJESTROWANA
                R.id.rb_jdg_skala -> ActivityType.JDG_SKALA
                R.id.rb_jdg_liniowy -> ActivityType.JDG_LINIOWY
                R.id.rb_jdg_ryczalt -> ActivityType.JDG_RYCZALT
                else -> ActivityType.NIEZAREJESTROWANA
            }
            ActivityTypeHelper.set(prefs, type)
            updateRyczaltFieldVisibility(type)
        }
    }

    private fun updateRyczaltFieldVisibility(type: ActivityType) {
        findViewById<View>(R.id.layout_ryczalt_rate).visibility =
            if (type == ActivityType.JDG_RYCZALT) View.VISIBLE else View.GONE
    }

    private fun setupMinWage() {
        findViewById<EditText>(R.id.et_min_wage).setText(
            ActivityTypeHelper.getMinWage(prefs).toString()
        )
        updateMonthlyLimitPreview()
    }

    private fun updateMonthlyLimitPreview() {
        val limit = ActivityTypeHelper.nierejestrowanaMonthlyLimit(prefs)
        findViewById<TextView>(R.id.tv_monthly_limit_preview).text =
            getString(R.string.monthly_limit_preview, limit)
    }
}
