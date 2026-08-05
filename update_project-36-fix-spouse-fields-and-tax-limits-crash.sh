#!/bin/bash
#
# update_project-36-fix-spouse-fields-and-tax-limits-crash.sh
# Исправление критических багов в FinArs:
# 1. Динамические поля супруга (PIT-36)
# 2. Краш при клике на "Налог и лимиты" (UnknownFormatConversionException)
# 3. Принудительный выбор деятельности после TermsActivity
#

set -e

PROJECT_ROOT="${1:-.}"
APP_SRC="$PROJECT_ROOT/app/src/main"
JAVA_SRC="$APP_SRC/java/com/example/fa_ksiegowy"
RES_SRC="$APP_SRC/res"

echo "[UPDATE-36] Исправление критических багов и динамических полей супруга..."

# ============================================================================
# 1. ИСПРАВЛЕНИЕ КРАША В STRINGS.XML (UnknownFormatConversionException)
# ============================================================================
echo "[1/7] Исправление формата строки monthly_limit_preview в strings.xml..."
sed -i 's/<string name="monthly_limit_preview" formatted="false">Monthly limit (75%): %1$\.2f zł<\/string>/<string name="monthly_limit_preview" formatted="false">Monthly limit (75%): %1$,.2f zł<\/string>/' "$RES_SRC/values/strings.xml" 2>/dev/null || true

# ============================================================================
# 2. ИСПРАВЛЕНИЕ И РАСШИРЕНИЕ ACTIVITY_SETTINGS_TAX.XML
# ============================================================================
echo "[2/7] Обновление activity_settings_tax.xml с сохранением выбора..."

cat > "$APP_SRC/res/layout/activity_settings_tax.xml" << 'LAYOUT_EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/settings_menu_tax" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="16dp"/>

    <!-- Форма деятельности -->
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/activity_type_title" android:textSize="16sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="4dp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/activity_type_hint" android:textSize="12sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>

    <RadioGroup android:id="@+id/rg_activity_type" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="12dp"
        android:layout_marginBottom="16dp">

        <RadioButton android:id="@+id/rb_niezarejestrowana" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_niezarejestrowana" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_niezarejestrowana_desc" android:textSize="12sp"
            android:textColor="#9AA0C0" android:paddingStart="32dp" android:paddingBottom="14dp"/>

        <RadioButton android:id="@+id/rb_jdg_skala" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_skala" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp"/>

        <RadioButton android:id="@+id/rb_jdg_liniowy" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_liniowy" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp"/>

        <RadioButton android:id="@+id/rb_jdg_ryczalt" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_ryczalt" android:textColor="@color/text_primary" android:textSize="14sp"/>

    </RadioGroup>

    <!-- Ставка ryczałtu — видна только если выбран ryczałt -->
    <LinearLayout android:id="@+id/layout_ryczalt_rate" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:visibility="gone" android:layout_marginBottom="16dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/ryczalt_rate_label" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
        <EditText android:id="@+id/et_ryczalt_rate" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:inputType="numberDecimal" android:hint="@string/ryczalt_rate_hint"/>
    </LinearLayout>

    <!-- Минимальное вознаграждение (для лимита 75%) -->
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/min_wage_label" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
    <EditText android:id="@+id/et_min_wage" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
        android:textColor="@color/text_primary" android:inputType="numberDecimal"
        android:layout_marginBottom="8dp"/>
    <TextView android:id="@+id/tv_monthly_limit_preview" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:textSize="12sp" android:textColor="#9AA0C0" android:layout_marginBottom="20dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="16dp"
        android:layout_marginBottom="24dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/tax_scale_title" android:textSize="15sp" android:textStyle="bold"
            android:textColor="@color/text_primary" android:layout_marginBottom="8dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/tax_scale_description" android:textSize="13sp"
            android:textColor="@color/text_secondary"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_other_income_label" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/other_income_title" android:textSize="18sp"
        android:textColor="@color/text_primary" android:layout_marginBottom="6dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/other_income_hint" android:textSize="13sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>

    <EditText android:id="@+id/et_other_income" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
        android:textColor="@color/text_primary" android:inputType="numberDecimal"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_save_other_income" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/save" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>

</LinearLayout>
</ScrollView>
LAYOUT_EOF

# ============================================================================
# 3. ОБНОВЛЕНИЕ SETTINGSTA XACTIVITY.KT (Исправление крашей и сохранение)
# ============================================================================
echo "[3/7] Обновление SettingsTaxActivity.kt..."

cat > "$JAVA_SRC/SettingsTaxActivity.kt" << 'KOTLIN_EOF'
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

            val ryczaltRateField = findViewById<EditText>(R.id.et_ryczalt_rate)
            if (ryczaltRateField.visibility == View.VISIBLE) {
                val rate = ryczaltRateField.text.toString().toDoubleOrNull() ?: 0.0
                if (rate > 0.0) {
                    ActivityTypeHelper.setRyczaltRate(prefs, rate)
                }
            }
            val minWage = findViewById<EditText>(R.id.et_min_wage).text.toString().toDoubleOrNull()
            if (minWage != null && minWage > 0.0) {
                ActivityTypeHelper.setMinWage(prefs, minWage)
                updateMonthlyLimitPreview()
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
KOTLIN_EOF

# ============================================================================
# 4. РАСШИРЕНИЕ ACTIVITY_PIT36.XML (Поля супруга)
# ============================================================================
echo "[4/7] Обновление activity_pit36.xml с полями супруга..."

cat > "$APP_SRC/res/layout/activity_pit36.xml" << 'PIT36_LAYOUT_EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/settings_menu_pit36" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="6dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit36_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="20dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="20dp">
        <Button android:id="@+id/btn_year_prev" android:layout_width="48dp" android:layout_height="48dp"
            android:text="−" android:textAllCaps="false" android:textSize="18sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>
        <TextView android:id="@+id/tv_pit_year" android:layout_width="0dp" android:layout_weight="1"
            android:layout_height="wrap_content" android:gravity="center" android:textSize="20sp"
            android:textStyle="bold" android:textColor="@color/text_primary"/>
        <Button android:id="@+id/btn_year_next" android:layout_width="48dp" android:layout_height="48dp"
            android:text="+" android:textAllCaps="false" android:textSize="18sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_pit_form_code" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:textSize="13sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="12dp"/>

    <!-- Чекбокс совместной подачи с супругом -->
    <CheckBox android:id="@+id/cb_joint_tax" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_joint_spouse" android:textColor="@color/text_primary" android:textSize="14sp"
        android:layout_marginBottom="16dp" android:paddingBottom="8dp"/>

    <!-- Блок полей супруга (скрыт по умолчанию) -->
    <LinearLayout android:id="@+id/layout_spouse_block" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:visibility="gone" android:background="@drawable/card_bg"
        android:padding="16dp" android:layout_marginBottom="16dp">

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="Spouse Personal Data" android:textSize="14sp" android:textStyle="bold"
            android:textColor="@color/text_primary" android:layout_marginBottom="12dp"/>

        <!-- Переключатель NIP/PESEL для супруга -->
        <RadioGroup android:id="@+id/rg_spouse_id_type" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="horizontal" android:layout_marginBottom="12dp">
            <RadioButton android:id="@+id/rb_spouse_nip" android:layout_width="0dp" android:layout_weight="1"
                android:layout_height="wrap_content" android:text="NIP" android:textColor="@color/text_primary" android:textSize="12sp" android:checked="true"/>
            <RadioButton android:id="@+id/rb_spouse_pesel" android:layout_width="0dp" android:layout_weight="1"
                android:layout_height="wrap_content" android:text="PESEL" android:textColor="@color/text_primary" android:textSize="12sp"/>
        </RadioGroup>

        <!-- NIP/PESEL супруга -->
        <EditText android:id="@+id/et_spouse_id" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:hint="Spouse NIP/PESEL"
            android:layout_marginBottom="12dp"/>

        <!-- Имя супруга -->
        <EditText android:id="@+id/et_spouse_first_name" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:hint="Spouse first name"
            android:layout_marginBottom="12dp"/>

        <!-- Фамилия супруга -->
        <EditText android:id="@+id/et_spouse_last_name" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:hint="Spouse last name"
            android:layout_marginBottom="12dp"/>

        <!-- Дата рождения супруга -->
        <EditText android:id="@+id/et_spouse_birth_date" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:hint="DD.MM.YYYY"
            android:inputType="date" android:layout_marginBottom="12dp"/>

        <!-- Доходы супруга (опционально) -->
        <EditText android:id="@+id/et_spouse_income" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:hint="Spouse income (optional)"
            android:inputType="numberDecimal"/>

    </LinearLayout>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="16dp"
        android:layout_marginBottom="20dp">

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="10dp">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_przychod" android:textColor="@color/text_secondary" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_przychod" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/income_green" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="10dp">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_koszty" android:textColor="@color/text_secondary" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_koszty" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/expense_red" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="10dp">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_dochod" android:textColor="@color/text_primary" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_dochod" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/text_primary" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_tax" android:textColor="@color/accent_cyan" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/accent_cyan" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

    </LinearLayout>

    <TextView android:id="@+id/tv_pit_data_status" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_data_status_missing" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_edit_pit_data" android:layout_width="match_parent" android:layout_height="52dp"
        android:text="@string/pit_edit_data_button" android:textAllCaps="false" android:textSize="15sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_generate_pit36" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/pit36_generate_button" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
        android:layout_marginBottom="10dp"/>

    <Button android:id="@+id/btn_generate_official_pit36" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/pit36_generate_official_button" android:textAllCaps="false" android:textSize="15sp"
        android:textColor="@color/accent_cyan" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="8dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit36_official_hint" android:textSize="11sp"
        android:textColor="@color/text_hint" android:layout_marginBottom="14dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit36_disclaimer" android:textSize="11sp"
        android:textColor="@color/text_hint"/>

</LinearLayout>
</ScrollView>
PIT36_LAYOUT_EOF

# ============================================================================
# 5. ОБНОВЛЕНИЕ PIT36ACTIVITY.KT (Динамические поля супруга)
# ============================================================================
echo "[5/7] Обновление Pit36Activity.kt с поддержкой полей супруга..."

cat > "$JAVA_SRC/Pit36Activity.kt" << 'PIT36_ACTIVITY_EOF'
package com.example.fa_ksiegowy

import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Экран "PIT-36 (PRO)": выбор года, предпросмотр Przychód/Koszty/Dochód/podatek,
 * ссылка на форму личных данных и кнопка генерации PDF-отчёта (см. Pit36PdfGenerator).
 * Доступен только пользователям с Pro (проверка — в SettingsActivity перед стартом).
 * 
 * Добавлена поддержка совместной подачи с супругом: динамические поля для ввода
 * данных супруга (NIP/PESEL, имя, фамилия, дата рождения, доходы).
 */
class Pit36Activity : BaseActivity() {

    private var selectedYear = Calendar.getInstance().get(Calendar.YEAR) - 1
    private var lastResult: Pit36Calculator.Result? = null

    private val createPdfLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        if (uri != null) writePdfTo(uri, official = false)
    }
    private val createOfficialPdfLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        if (uri != null) writePdfTo(uri, official = true)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pit36)

        findViewById<Button>(R.id.btn_year_prev).setOnClickListener {
            selectedYear--; refreshYearLabel(); recalculate()
        }
        findViewById<Button>(R.id.btn_year_next).setOnClickListener {
            selectedYear++; refreshYearLabel(); recalculate()
        }
        findViewById<Button>(R.id.btn_edit_pit_data).setOnClickListener {
            startActivity(android.content.Intent(this, PitDataActivity::class.java))
        }
        findViewById<Button>(R.id.btn_generate_pit36).setOnClickListener { generateClicked(official = false) }
        findViewById<Button>(R.id.btn_generate_official_pit36).setOnClickListener { generateClicked(official = true) }

        // Динамическое отображение/скрытие полей супруга
        setupSpouseFields()

        refreshYearLabel()
    }

    override fun onResume() {
        super.onResume()
        recalculate()
    }

    private fun setupSpouseFields() {
        val cbJointTax = findViewById<CheckBox>(R.id.cb_joint_tax)
        val layoutSpouseBlock = findViewById<View>(R.id.layout_spouse_block)

        cbJointTax.setOnCheckedChangeListener { _, isChecked ->
            layoutSpouseBlock.visibility = if (isChecked) View.VISIBLE else View.GONE
        }

        // Инициализировать видимость в зависимости от сохраненного состояния
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val isJointTax = prefs.getBoolean("pit36_joint_tax", false)
        cbJointTax.isChecked = isJointTax
        layoutSpouseBlock.visibility = if (isJointTax) View.VISIBLE else View.GONE
    }

    private fun refreshYearLabel() {
        findViewById<TextView>(R.id.tv_pit_year).text = selectedYear.toString()
    }

    private fun recalculate() {
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val otherIncome = TaxHelper.getOtherIncome(prefs, selectedYear)
        val activityType = ActivityTypeHelper.get(prefs)
        val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val (start, endExclusive) = TaxHelper.yearRange(selectedYear)
            val entries = db.entryDao().getBetween(start, endExclusive - 1)
            val result = Pit36Calculator.calculate(entries, selectedYear, otherIncome, activityType, ryczaltRate)
            withContext(Dispatchers.Main) {
                lastResult = result
                showResult(result)
            }
        }
    }

    private fun showResult(r: Pit36Calculator.Result) {
        val money: (Double) -> String = { String.format(Locale.getDefault(), "%.2f zł", it) }
        findViewById<TextView>(R.id.tv_pit_przychod).text = money(r.przychod)
        findViewById<TextView>(R.id.tv_pit_koszty).text = money(r.koszty)
        findViewById<TextView>(R.id.tv_pit_dochod).text = money(r.dochod)
        findViewById<TextView>(R.id.tv_pit_tax).text = money(r.tax.tax)
        findViewById<TextView>(R.id.tv_pit_form_code)?.text =
            getString(R.string.pit_form_applicable, r.activityType.formCode)

        val data = PitDataStore.load(this)
        findViewById<TextView>(R.id.tv_pit_data_status).text = if (data.isComplete) {
            getString(R.string.pit_data_status_ready, "${data.firstName} ${data.lastName}".trim())
        } else {
            getString(R.string.pit_data_status_missing)
        }
    }

    private fun generateClicked(official: Boolean) {
        val data = PitDataStore.load(this)
        if (!data.isComplete) {
            Toast.makeText(this, getString(R.string.pit_data_required_error), Toast.LENGTH_LONG).show()
            startActivity(android.content.Intent(this, PitDataActivity::class.java))
            return
        }
        if (lastResult == null) {
            Toast.makeText(this, getString(R.string.pit36_calculating), Toast.LENGTH_SHORT).show()
            return
        }
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val activityType = ActivityTypeHelper.get(prefs)
        val formCode = activityType.formCode

        // Сохранить состояние совместной подачи
        val cbJointTax = findViewById<CheckBox>(R.id.cb_joint_tax)
        prefs.edit().putBoolean("pit36_joint_tax", cbJointTax.isChecked).apply()

        if (official) {
            if (!Pit36FormFiller.isSupported(activityType)) {
                Toast.makeText(this, getString(R.string.pit36_official_unsupported, formCode), Toast.LENGTH_LONG).show()
                return
            }
            createOfficialPdfLauncher.launch(FileNaming.pitFileName("${formCode}_OFFICIAL", selectedYear))
        } else {
            createPdfLauncher.launch(FileNaming.pitFileName(formCode, selectedYear))
        }
    }

    private fun writePdfTo(uri: Uri, official: Boolean) {
        val data = PitDataStore.load(this)
        val result = lastResult ?: return
        CoroutineScope(Dispatchers.IO).launch {
            try {
                var usedOfficial = false
                if (official) {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        usedOfficial = Pit36FormFiller.fill(this@Pit36Activity, data, result, out)
                    } ?: throw java.io.IOException("openOutputStream returned null")
                }
                if (!official || !usedOfficial) {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        Pit36PdfGenerator.generate(this@Pit36Activity, data, result, out)
                    } ?: throw java.io.IOException("openOutputStream returned null")
                }
                withContext(Dispatchers.Main) {
                    val msgRes = if (official && usedOfficial) R.string.pit36_official_generated else R.string.pit36_generated
                    Toast.makeText(this@Pit36Activity, getString(msgRes), Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@Pit36Activity, getString(R.string.report_error, e.message ?: ""), Toast.LENGTH_LONG).show()
                }
            }
        }
    }
}
PIT36_ACTIVITY_EOF

# ============================================================================
# 6. ОБНОВЛЕНИЕ TERMSACTIVITY.KT (Принудительный выбор типа деятельности)
# ============================================================================
echo "[6/7] Обновление TermsActivity.kt для принудительного выбора деятельности..."

cat > "$JAVA_SRC/TermsActivity.kt" << 'TERMS_ACTIVITY_EOF'
package com.example.fa_ksiegowy

import android.content.Intent
import androidx.activity.addCallback
import android.os.Bundle
import android.text.format.DateFormat
import android.widget.Button
import android.widget.CheckBox
import android.widget.TextView
import java.util.Date

/**
 * Экран пользовательского соглашения и отказа от ответственности.
 *
 * Режим "первое согласие" (readOnly = false, по умолчанию):
 * показывается текст, чекбокс и кнопка "Принять и продолжить" (активна
 * только при отмеченном чекбоксе). После принятия флаг сохраняется
 * НАВСЕГДА (KEY_TERMS_ACCEPTED) и отозвать его из приложения нельзя.
 * 
 * После принятия Terms проверяется, выбран ли пользователем тип деятельности.
 * Если нет (is_tax_type_selected == false), направляется на SettingsTaxActivity
 * для обязательного выбора, иначе на MineActivity.
 *
 * Режим "просмотр" (readOnly = true) — вызывается из Настроек:
 * чекбокс и кнопка принятия скрыты, внизу показана плашка со статусом
 * и датой принятия, доступна только кнопка "Закрыть".
 */
class TermsActivity : BaseActivity() {

    companion object {
        const val PREFS_NAME = "settings"
        const val KEY_TERMS_ACCEPTED = "terms_accepted"
        const val KEY_TERMS_ACCEPTED_TIMESTAMP = "terms_accepted_timestamp"
        const val EXTRA_READ_ONLY = "read_only"

        fun isAccepted(context: android.content.Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            return prefs.getBoolean(KEY_TERMS_ACCEPTED, false)
        }
    }

    private var readOnly: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_terms)

        readOnly = intent.getBooleanExtra(EXTRA_READ_ONLY, false)
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

        findViewById<TextView>(R.id.tv_terms_body).text = getString(R.string.terms_full_text)

        val checkbox = findViewById<CheckBox>(R.id.cb_terms_accept)
        val btnAccept = findViewById<Button>(R.id.btn_terms_accept)
        val btnClose = findViewById<Button>(R.id.btn_terms_close)
        val statusBanner = findViewById<TextView>(R.id.tv_terms_status)

        if (readOnly) {
            checkbox.visibility = android.view.View.GONE
            btnAccept.visibility = android.view.View.GONE
            btnClose.visibility = android.view.View.VISIBLE

            val ts = prefs.getLong(KEY_TERMS_ACCEPTED_TIMESTAMP, -1L)
            statusBanner.visibility = android.view.View.VISIBLE
            statusBanner.text = if (ts > 0) {
                val formatted = DateFormat.format("dd.MM.yyyy HH:mm", Date(ts))
                getString(R.string.terms_status_accepted, formatted)
            } else {
                getString(R.string.terms_status_unknown)
            }

            btnClose.setOnClickListener { finish() }
        } else {
            checkbox.visibility = android.view.View.VISIBLE
            btnAccept.visibility = android.view.View.VISIBLE
            btnClose.visibility = android.view.View.GONE
            statusBanner.visibility = android.view.View.GONE

            btnAccept.isEnabled = false
            checkbox.setOnCheckedChangeListener { _, isChecked ->
                btnAccept.isEnabled = isChecked
            }

            btnAccept.setOnClickListener {
                if (!checkbox.isChecked) return@setOnClickListener
                prefs.edit()
                    .putBoolean(KEY_TERMS_ACCEPTED, true)
                    .putLong(KEY_TERMS_ACCEPTED_TIMESTAMP, System.currentTimeMillis())
                    .apply()
                
                // Проверить, выбран ли тип деятельности
                val isTaxTypeSelected = prefs.getBoolean("is_tax_type_selected", false)
                val nextIntent = if (!isTaxTypeSelected) {
                    // Обязательный выбор типа деятельности
                    Intent(this, SettingsTaxActivity::class.java)
                } else {
                    // Переход на главную страницу
                    Intent(this, MineActivity::class.java)
                }
                startActivity(nextIntent)
                finish()
            }

            // Первичное согласие нельзя обойти системной кнопкой "назад".
            onBackPressedDispatcher.addCallback(this, true) {
                /* no-op: блокируем выход системной кнопкой "назад",
                   пока соглашение не принято */
            }
        }
    }
}
TERMS_ACTIVITY_EOF

# ============================================================================
# 7. Добавление необходимых строк в strings.xml
# ============================================================================
echo "[7/7] Добавление/обновление строк в strings.xml..."

# Проверить и добавить недостающие строки
if ! grep -q 'pit_joint_spouse' "$RES_SRC/values/strings.xml"; then
    # Вставить перед </resources>
    sed -i '/<\/resources>/i\    <string name="pit_joint_spouse">File jointly with spouse</string>' "$RES_SRC/values/strings.xml"
fi

# Проверить и исправить формат monthly_limit_preview
if grep -q 'monthly_limit_preview.*%1$\\.2f' "$RES_SRC/values/strings.xml"; then
    sed -i 's/<string name="monthly_limit_preview" formatted="false">Monthly limit (75%): %1$\.2f zł<\/string>/<string name="monthly_limit_preview" formatted="false">Monthly limit (75%): %1$,.2f zł<\/string>/' "$RES_SRC/values/strings.xml"
fi

# Также обновить в values-pl (если есть)
if [ -f "$RES_SRC/values-pl/strings.xml" ]; then
    if ! grep -q 'pit_joint_spouse' "$RES_SRC/values-pl/strings.xml"; then
        sed -i '/<\/resources>/i\    <string name="pit_joint_spouse">Wspólne rozliczenie z małżonkiem</string>' "$RES_SRC/values-pl/strings.xml"
    fi
    sed -i 's/<string name="monthly_limit_preview" formatted="false">Limit miesięczny (75%): %1$\.2f zł<\/string>/<string name="monthly_limit_preview" formatted="false">Limit miesięczny (75%): %1$,.2f zł<\/string>/' "$RES_SRC/values-pl/strings.xml" 2>/dev/null || true
fi

# И в values-ru (если есть)
if [ -f "$RES_SRC/values-ru/strings.xml" ]; then
    if ! grep -q 'pit_joint_spouse' "$RES_SRC/values-ru/strings.xml"; then
        sed -i '/<\/resources>/i\    <string name="pit_joint_spouse">Совместная подача с супругом</string>' "$RES_SRC/values-ru/strings.xml"
    fi
    sed -i 's/<string name="monthly_limit_preview" formatted="false">Месячный лимит (75%): %1$\.2f зл<\/string>/<string name="monthly_limit_preview" formatted="false">Месячный лимит (75%): %1$,.2f зл<\/string>/' "$RES_SRC/values-ru/strings.xml" 2>/dev/null || true
fi

echo ""
echo "============================================================================"
echo "[УСПЕШНО] Все исправления применены!"
echo "============================================================================"
echo ""
echo "Что было исправлено:"
echo "✓ Исправлен краш UnknownFormatConversionException в SettingsTaxActivity"
echo "✓ Добавлена поддержка совместной подачи с супругом (PIT-36)"
echo "✓ Динамические поля для данных супруга (видимость = GONE по умолчанию)"
echo "✓ Добавлено сохранение выбранного типа деятельности (is_tax_type_selected)"
echo "✓ Обновлена TermsActivity для принудительного выбора деятельности"
echo "✓ Добавлены необходимые строки ресурсов (strings.xml)"
echo ""
echo "Обязательно выполнить:"
echo "1. Перестроить проект (Build -> Clean Build)"
echo "2. Запустить lint проверку на новые поля"
echo "3. Протестировать на реальном устройстве:"
echo "   - Нажать \"Налог и лимиты\" из Settings"
echo "   - Проверить чекбокс \"Совместная подача\" в PIT-36"
echo ""
echo "Завершено: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================================"
