package com.example.fa_ksiegowy

import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
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
        setupVatCompliance()
        setupKasaCompliance()
        setupPushFrequency()

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
            // Rejestracja JDG (skala/liniowy/ryczałt) od razu odblokowuje możliwość
            // potwierdzenia posiadania kasy fiskalnej — nie trzeba czekać na
            // przekroczenie limitu 20 000 zł, patrz setupKasaCompliance().
            setupKasaCompliance()
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

    override fun onResume() {
        super.onResume()
        // Лимит мог быть превышен, пока пользователь был на другом экране (например,
        // сразу после выставления фактуры) — перепроверяем видимость блока при возврате.
        setupVatCompliance()
        setupKasaCompliance()
    }

    /**
     * Блок подтверждения регистрации VAT: появляется только после превышения
     * годового лимита zwolnienia z VAT (240 000 zł) — либо если подтверждение
     * уже было дано ранее (тогда чекбокс показывается заблокированным как
     * информация о статусе, без возможности снять галочку).
     */
    private fun setupVatCompliance() {
        val layout = findViewById<View>(R.id.layout_vat_compliance)
        val cb = findViewById<CheckBox>(R.id.cb_vat_registered)
        val alreadyConfirmed = VatComplianceHelper.isVatRegisteredConfirmed(prefs)
        if (alreadyConfirmed) {
            layout.visibility = View.VISIBLE
            cb.setOnCheckedChangeListener(null)
            cb.isChecked = true
            cb.isEnabled = false
            cb.text = getString(R.string.cb_vat_registered_confirmed_label)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            val limits = LimitsHelper.compute(applicationContext)
            withContext(Dispatchers.Main) {
                layout.visibility = if (limits.vat.exceeded) View.VISIBLE else View.GONE
                cb.isChecked = false
                cb.isEnabled = true
                cb.text = getString(R.string.cb_vat_registered_label)
                cb.setOnCheckedChangeListener { _, checked ->
                    if (checked) {
                        AppDialog.show(
                            context = this@SettingsTaxActivity,
                            title = getString(R.string.vat_confirm_dialog_title),
                            message = getString(R.string.vat_confirm_dialog_message),
                            positiveText = getString(R.string.confirm_yes),
                            onPositive = {
                                VatComplianceHelper.confirmVatRegistered(prefs)
                                setupVatCompliance()
                            },
                            negativeText = getString(R.string.confirm_cancel),
                            onNegative = { cb.isChecked = false }
                        )
                    }
                }
            }
        }
    }

    /**
     * Блок подtwierdzenia posiadania kasy fiskalnej, analogicznie do
     * [setupVatCompliance]. Widoczność zależy od formy działalności:
     *
     *  - Zarejestrowana JDG (skala/liniowy/ryczałt) — блок показывается СРАЗУ,
     *    как только wybrano ten typ w ustawieniach, niezależnie od limitu
     *    gotówki. Zarejestrowany od początku przedsiębiorca mógł już mieć
     *    kasę fiskalną, więc powinien mieć możliwość to potwierdzić od razu —
     *    a po potwierdzeniu w AddInvoiceActivity pojawia się przełącznik
     *    "wydana do paragonu" (zob. VatComplianceHelper.allowsReceiptFlag).
     *  - Niezarejestrowana (działalność nierejestrowana) — блок pojawia się
     *    dopiero PO przekroczeniu rocznego limitu 20 000 zł sprzedaży
     *    gotówkowej dla osób fizycznych (zob. CashLimitHelper), tak jak
     *    dotychczas.
     */
    private fun setupKasaCompliance() {
        val layout = findViewById<View>(R.id.layout_kasa_compliance)
        val hint = findViewById<TextView>(R.id.tv_kasa_compliance_hint)
        val cb = findViewById<CheckBox>(R.id.cb_kasa_fiskalna)
        val alreadyConfirmed = VatComplianceHelper.isKasaFiskalnaConfirmed(prefs)
        if (alreadyConfirmed) {
            layout.visibility = View.VISIBLE
            cb.setOnCheckedChangeListener(null)
            cb.isChecked = true
            cb.isEnabled = false
            cb.text = getString(R.string.cb_kasa_confirmed_label)
            return
        }

        val activityType = ActivityTypeHelper.get(prefs)
        if (activityType.isRegisteredJdg) {
            // Zarejestrowana JDG — nie czekamy na przekroczenie limitu gotówki,
            // pokazujemy potwierdzenie od razu.
            hint.text = getString(R.string.kasa_compliance_hint_registered)
            layout.visibility = View.VISIBLE
            bindKasaCheckbox(cb)
            return
        }

        // Niezarejestrowana — jak dotychczas, dopiero po przekroczeniu 20 000 zł.
        hint.text = getString(R.string.kasa_compliance_hint)
        CoroutineScope(Dispatchers.IO).launch {
            val cash = CashLimitHelper.computeCurrentYear(applicationContext)
            withContext(Dispatchers.Main) {
                // Typ działalności mógł się zmienić, zanim ta korutyna się zakończyła
                // (np. użytkownik szybko przełączył RadioGroup) — sprawdzamy jeszcze raz,
                // żeby nie nadpisać stanu ustawionego już dla zarejestrowanej JDG.
                if (ActivityTypeHelper.get(prefs).isRegisteredJdg) return@withContext
                layout.visibility = if (cash.exceeded) View.VISIBLE else View.GONE
                bindKasaCheckbox(cb)
            }
        }
    }

    /** Wspólna konfiguracja checkboxa potwierdzenia kasy fiskalnej (stan odznaczony,
     *  aktywny, z dialogiem potwierdzającym) — używana zarówno dla zarejestrowanej
     *  JDG, jak i dla niezarejestrowanej po przekroczeniu limitu. */
    private fun bindKasaCheckbox(cb: CheckBox) {
        cb.isChecked = false
        cb.isEnabled = true
        cb.text = getString(R.string.cb_kasa_label)
        cb.setOnCheckedChangeListener { _, checked ->
            if (checked) {
                AppDialog.show(
                    context = this@SettingsTaxActivity,
                    title = getString(R.string.kasa_confirm_dialog_title),
                    message = getString(R.string.kasa_confirm_dialog_message),
                    positiveText = getString(R.string.confirm_yes),
                    onPositive = {
                        VatComplianceHelper.confirmKasaFiskalna(prefs)
                        setupKasaCompliance()
                    },
                    negativeText = getString(R.string.confirm_cancel),
                    onNegative = { cb.isChecked = false }
                )
            }
        }
    }

    /** Częstotliwość powiadomień push (ile razy dziennie mogą przychodzić alerty
     *  o przekroczonych limitach i zaległych fakturach) — zob. VatComplianceHelper. */
    private fun setupPushFrequency() {
        val et = findViewById<EditText>(R.id.et_push_frequency)
        et.setText(VatComplianceHelper.getPushFrequency(prefs).toString())
        findViewById<Button>(R.id.btn_save_push_frequency).setOnClickListener {
            val value = et.text.toString().toIntOrNull()
            if (value == null || value < 1) {
                Toast.makeText(this, getString(R.string.push_frequency_invalid), Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            VatComplianceHelper.setPushFrequency(prefs, value)
            et.setText(VatComplianceHelper.getPushFrequency(prefs).toString())
            Toast.makeText(this, getString(R.string.push_frequency_saved), Toast.LENGTH_SHORT).show()
        }
    }
}
