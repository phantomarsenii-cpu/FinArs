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
 *  2) Минимальное вознаграждение (minimalne wynagrodzenie) и месячный лимит 75% —
 *     ЭТО АКТУАЛЬНО ТОЛЬКО ДЛЯ NIEZAREJESTROWANA (лимит přychodu, при превышении
 *     которого возникает обязанность зарегистрировать JDG). Для любого из трёх
 *     вариантов Zarejestrowana JDG (skala/liniowy/ryczałt) этот блок скрыт — у
 *     зарегистрированной деятельности такого месячного лимита просто нет.
 *  3) Ставки ryczałtu больше НЕ настраиваются здесь одной общей цифрой — теперь
 *     категория (и, соответственно, ставка 3%/5,5%/8,5%/12%/14%/17%) выбирается
 *     для каждой операции дохода отдельно — см. AddEntryActivity (доход) и
 *     AddInvoiceActivity (позиция фактуры). Это важно, так как один человек может
 *     одновременно продавать товары и оказывать услуги с разными ставками.
 *  4) "Прочие доходы" — как и раньше, влияют на то, какая часть прибыли
 *     из приложения облагается по 12%, а какая — по 32% (только для skali).
 *
 * Налог всегда считается автоматически по официальной формуле для выбранной
 * формы (см. TaxHelper) — ручного ввода единого процента ryczałtu больше нет.
 */
class SettingsTaxActivity : BaseActivity() {
    private lateinit var prefs: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_tax)
        prefs = getSharedPreferences("settings", MODE_PRIVATE)

        val year = TaxHelper.currentYear()
        try {
            findViewById<TextView>(R.id.tv_other_income_label).text =
                getString(R.string.other_income_label, year)
        } catch (e: Exception) {
            // Fallback if string resource has invalid format
            findViewById<TextView>(R.id.tv_other_income_label).text = 
                "Other income ($year)"
        }

        setupActivityType()
        setupMinWage()

        val etOtherIncome = findViewById<EditText>(R.id.et_other_income)
        etOtherIncome.setText(TaxHelper.getOtherIncome(prefs, year).toString())
        findViewById<Button>(R.id.btn_save_other_income).setOnClickListener {
            val v = etOtherIncome.text.toString().toDoubleOrNull() ?: 0.0
            TaxHelper.setOtherIncome(prefs, year, v)

            // Minimalne wynagrodzenie учитывается только для niezarejestrowana —
            // для JDG блок скрыт (см. updateNierejestrowanaFieldsVisibility), поле
            // может быть невидимым, тогда его значение не сохраняем.
            val minWageField = findViewById<EditText>(R.id.et_min_wage)
            if (minWageField.visibility == View.VISIBLE) {
                val minWage = minWageField.text.toString().toDoubleOrNull()
                if (minWage != null && minWage > 0.0) {
                    ActivityTypeHelper.setMinWage(prefs, minWage)
                    updateMonthlyLimitPreview()
                }
            }

            // Отметить, что тип деятельности выбран
            prefs.edit()
                .putBoolean("is_tax_type_selected", true)
                .apply()

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
        updateNierejestrowanaFieldsVisibility(current)

        rg.setOnCheckedChangeListener { _, checkedId ->
            val type = when (checkedId) {
                R.id.rb_niezarejestrowana -> ActivityType.NIEZAREJESTROWANA
                R.id.rb_jdg_skala -> ActivityType.JDG_SKALA
                R.id.rb_jdg_liniowy -> ActivityType.JDG_LINIOWY
                R.id.rb_jdg_ryczalt -> ActivityType.JDG_RYCZALT
                else -> ActivityType.NIEZAREJESTROWANA
            }
            ActivityTypeHelper.set(prefs, type)
            updateNierejestrowanaFieldsVisibility(type)
        }
    }

    /** Блок "Minimalne wynagrodzenie / Monthly limit (75%)" нужен только для
     *  niezarejestrowana — для любого из трёх Zarejestrowana JDG (skala/liniowy/
     *  ryczałt) такого лимита не существует, поэтому блок полностью скрывается.
     *  Подсказка про перенос ставки ryczałtu показывается, только если выбран ryczałt. */
    private fun updateNierejestrowanaFieldsVisibility(type: ActivityType) {
        val visible = type == ActivityType.NIEZAREJESTROWANA
        findViewById<View>(R.id.layout_min_wage).visibility = if (visible) View.VISIBLE else View.GONE
        findViewById<View>(R.id.layout_ryczalt_rate_hint).visibility =
            if (type == ActivityType.JDG_RYCZALT) View.VISIBLE else View.GONE
    }

    private fun setupMinWage() {
        val etMinWage = findViewById<EditText>(R.id.et_min_wage)
        try {
            etMinWage.setText(
                String.format("%.2f", ActivityTypeHelper.getMinWage(prefs))
            )
        } catch (e: Exception) {
            etMinWage.setText("0.00")
        }
        updateMonthlyLimitPreview()
    }

    private fun updateMonthlyLimitPreview() {
        val tvPreview = findViewById<TextView>(R.id.tv_monthly_limit_preview)
        try {
            val limit = ActivityTypeHelper.nierejestrowanaMonthlyLimit(prefs)
            tvPreview.text = String.format("Monthly limit (75%%): %.2f zł", limit)
        } catch (e: Exception) {
            tvPreview.text = "Monthly limit: could not calculate"
        }
    }
}
