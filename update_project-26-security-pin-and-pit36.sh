#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 26: PIN/биометрия + генератор PIT-36 (Pro) ==="
echo "Добавляет: экран блокировки приложения (PIN + отпечаток/лицо),"
echo "и Pro-функцию генерации вспомогательного PDF-отчёта для PIT-36."
echo ""

if [ ! -f "app/build.gradle" ]; then
    echo "!!! Запусти скрипт из корня проекта (там, где app/build.gradle)"
    exit 1
fi

echo "--- 1/4: зависимость androidx.biometric ---"
if grep -q "androidx.biometric:biometric" app/build.gradle; then
    echo "-- уже добавлена, пропускаю"
else
    sed -i 's#implementation "com.google.android.ump:user-messaging-platform:3.1.0"#implementation "com.google.android.ump:user-messaging-platform:3.1.0"\n    implementation "androidx.biometric:biometric:1.1.0"#' app/build.gradle
    echo "OK: androidx.biometric:1.1.0 добавлена в app/build.gradle"
fi

echo "--- 2/4: новые файлы (Kotlin + layout) ---"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/SecurityHelper.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/SecurityHelper.kt" << 'EOF_SECURITYHELPER_KT'
package com.example.fa_ksiegowy

import android.content.Context
import androidx.biometric.BiometricManager
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Хранит PIN-код приложения (НЕ пароль от аккаунта — чисто локальная блокировка
 * экрана). PIN никогда не хранится в открытом виде: соль генерируется случайно
 * при первой установке PIN и хранится вместе с солёным SHA-256 хэшем в обычных
 * SharedPreferences (для самого хэша шифрование не требуется — по хэшу нельзя
 * восстановить исходный PIN).
 *
 * Отдельно — переключатель "вход по отпечатку/лицу" (biometric), который можно
 * включить только если PIN уже установлен (biometric — это быстрый способ ввести
 * тот же самый PIN, а не замена его: если сенсор недоступен, всегда можно ввести
 * PIN вручную).
 */
object SecurityHelper {

    private const val PREFS = "security"
    private const val KEY_SALT = "pin_salt"
    private const val KEY_HASH = "pin_hash"
    private const val KEY_BIOMETRIC_ENABLED = "biometric_enabled"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun hasPin(context: Context): Boolean =
        prefs(context).contains(KEY_HASH)

    /** Устанавливает/меняет PIN (4–6 цифр, проверка формата — на стороне UI). */
    fun setPin(context: Context, pin: String) {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val hash = hash(pin, salt)
        prefs(context).edit()
            .putString(KEY_SALT, salt.joinToString(",") { it.toString() })
            .putString(KEY_HASH, hash)
            .apply()
    }

    fun verifyPin(context: Context, pin: String): Boolean {
        val p = prefs(context)
        val saltStr = p.getString(KEY_SALT, null) ?: return false
        val expectedHash = p.getString(KEY_HASH, null) ?: return false
        val salt = saltStr.split(",").map { it.toByte() }.toByteArray()
        return hash(pin, salt) == expectedHash
    }

    /** Полностью отключает блокировку приложения (PIN + биометрию). */
    fun clearPin(context: Context) {
        prefs(context).edit()
            .remove(KEY_SALT)
            .remove(KEY_HASH)
            .remove(KEY_BIOMETRIC_ENABLED)
            .apply()
    }

    fun isBiometricEnabled(context: Context): Boolean =
        hasPin(context) && prefs(context).getBoolean(KEY_BIOMETRIC_ENABLED, false)

    fun setBiometricEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_BIOMETRIC_ENABLED, enabled).apply()
    }

    /** Есть ли на устройстве настроенный отпечаток/лицо, которым можно пользоваться. */
    fun isBiometricAvailable(context: Context): Boolean {
        val manager = BiometricManager.from(context)
        val result = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        return result == BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun hash(pin: String, salt: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(salt)
        val bytes = digest.digest(pin.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
EOF_SECURITYHELPER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/SecurityHelper.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AppLockState.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/AppLockState.kt" << 'EOF_APPLOCKSTATE_KT'
package com.example.fa_ksiegowy

import android.content.Context

/**
 * Отслеживает, сколько Activity сейчас "запущено" (started), чтобы понять,
 * когда приложение целиком уходит в фон и когда возвращается на передний план.
 * Как только счётчик переходит с 0 на 1 (приложение снова видно пользователю)
 * и PIN установлен — выставляем isLocked = true, и BaseActivity показывает
 * LockActivity поверх текущего экрана. Успешный ввод PIN/биометрии сбрасывает
 * isLocked обратно в false до следующего полного ухода в фон.
 */
object AppLockState {

    @Volatile
    var isLocked: Boolean = false
        internal set

    private var startedActivityCount = 0

    fun onActivityStarted(context: Context) {
        if (startedActivityCount == 0 && SecurityHelper.hasPin(context)) {
            isLocked = true
        }
        startedActivityCount++
    }

    fun onActivityStopped() {
        if (startedActivityCount > 0) startedActivityCount--
    }

    fun unlock() {
        isLocked = false
    }
}
EOF_APPLOCKSTATE_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/AppLockState.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/LockActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/LockActivity.kt" << 'EOF_LOCKACTIVITY_KT'
package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat

/**
 * Экран блокировки приложения. Показывается поверх любого экрана, когда
 * AppLockState.isLocked == true (см. BaseActivity). Не имеет пункта "Настройки"
 * или иного выхода, кроме правильного PIN/биометрии — кнопка "Назад" сворачивает
 * приложение (moveTaskToBack), а не закрывает этот экран.
 */
class LockActivity : BaseActivity() {

    private lateinit var etPin: EditText
    private lateinit var tvError: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_lock)

        etPin = findViewById(R.id.et_pin)
        tvError = findViewById(R.id.tv_lock_error)
        findViewById<ImageView>(R.id.iv_lock_logo).setImageResource(R.drawable.logo)

        findViewById<Button>(R.id.btn_unlock).setOnClickListener { tryUnlock() }
        etPin.setOnEditorActionListener { _, _, _ -> tryUnlock(); true }

        val btnBiometric = findViewById<Button>(R.id.btn_use_biometric)
        val canUseBiometric = SecurityHelper.isBiometricEnabled(this) && SecurityHelper.isBiometricAvailable(this)
        if (canUseBiometric) {
            btnBiometric.visibility = android.view.View.VISIBLE
            btnBiometric.setOnClickListener { showBiometricPrompt() }
        } else {
            btnBiometric.visibility = android.view.View.GONE
        }
    }

    override fun onStart() {
        super.onStart()
        // Автоматически предлагаем биометрию сразу при открытии экрана блокировки,
        // чтобы не заставлять лишний раз нажимать кнопку.
        if (SecurityHelper.isBiometricEnabled(this) && SecurityHelper.isBiometricAvailable(this)) {
            showBiometricPrompt()
        }
    }

    override fun onBackPressed() {
        // Не даём "выйти" из блокировки кнопкой назад — сворачиваем приложение.
        moveTaskToBack(true)
    }

    private fun tryUnlock() {
        val pin = etPin.text.toString()
        if (SecurityHelper.verifyPin(this, pin)) {
            AppLockState.unlock()
            finish()
        } else {
            tvError.visibility = android.view.View.VISIBLE
            etPin.text.clear()
        }
    }

    private fun showBiometricPrompt() {
        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(this, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                AppLockState.unlock()
                finish()
            }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                // Пользователь отменил/ошибка сенсора — просто остаёмся на вводе PIN.
            }
            override fun onAuthenticationFailed() {
                // Неверный отпечаток — ждём повторную попытку или ввод PIN.
            }
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.lock_biometric_prompt_title))
            .setSubtitle(getString(R.string.lock_biometric_prompt_subtitle))
            .setNegativeButtonText(getString(R.string.lock_use_pin))
            .build()
        prompt.authenticate(info)
    }
}
EOF_LOCKACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/LockActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/SettingsSecurityActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/SettingsSecurityActivity.kt" << 'EOF_SETTINGSSECURITYACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast

/**
 * Настройки блокировки приложения: включить/выключить PIN, сменить PIN,
 * включить вход по отпечатку/лицу (доступно только если PIN уже установлен
 * и устройство поддерживает биометрию).
 */
class SettingsSecurityActivity : BaseActivity() {

    private lateinit var switchPin: Switch
    private lateinit var switchBiometric: Switch
    private lateinit var tvChangePin: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_security)

        switchPin = findViewById(R.id.switch_pin)
        switchBiometric = findViewById(R.id.switch_biometric)
        tvChangePin = findViewById(R.id.tv_change_pin)

        refreshUi()
        tvChangePin.setOnClickListener { promptChangePin() }
    }

    override fun onResume() {
        super.onResume()
        refreshUi()
    }

    private fun refreshUi() {
        val hasPin = SecurityHelper.hasPin(this)
        switchPin.setOnCheckedChangeListener(null)
        switchPin.isChecked = hasPin
        switchPin.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked && !SecurityHelper.hasPin(this)) {
                promptSetNewPin()
            } else if (!isChecked && SecurityHelper.hasPin(this)) {
                promptDisablePin()
            }
        }

        switchBiometric.isEnabled = hasPin
        switchBiometric.setOnCheckedChangeListener(null)
        switchBiometric.isChecked = SecurityHelper.isBiometricEnabled(this)
        switchBiometric.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked && !SecurityHelper.isBiometricAvailable(this)) {
                Toast.makeText(this, getString(R.string.lock_biometric_unavailable), Toast.LENGTH_LONG).show()
                switchBiometric.isChecked = false
                return@setOnCheckedChangeListener
            }
            SecurityHelper.setBiometricEnabled(this, isChecked)
        }

        tvChangePin.visibility = if (hasPin) android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun pinInput(): EditText = EditText(this).apply {
        inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
        hint = getString(R.string.lock_pin_hint)
    }

    private fun wrap(view: EditText): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(48, 24, 48, 0)
        addView(view)
    }

    private fun promptSetNewPin() {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_set_pin_title))
            .setMessage(getString(R.string.security_set_pin_message))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                val pin = input.text.toString()
                if (pin.length < 4 || pin.length > 6) {
                    Toast.makeText(this, getString(R.string.security_pin_length_error), Toast.LENGTH_LONG).show()
                    refreshUi()
                    return@setPositiveButton
                }
                confirmNewPin(pin)
            }
            .setNegativeButton(getString(R.string.dialog_close)) { _, _ -> refreshUi() }
            .setOnCancelListener { refreshUi() }
            .show()
    }

    private fun confirmNewPin(firstPin: String) {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_confirm_pin_title))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                if (input.text.toString() == firstPin) {
                    SecurityHelper.setPin(this, firstPin)
                    Toast.makeText(this, getString(R.string.security_pin_saved), Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, getString(R.string.security_pin_mismatch), Toast.LENGTH_LONG).show()
                }
                refreshUi()
            }
            .setNegativeButton(getString(R.string.dialog_close)) { _, _ -> refreshUi() }
            .setOnCancelListener { refreshUi() }
            .show()
    }

    private fun promptDisablePin() {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_disable_pin_title))
            .setMessage(getString(R.string.security_enter_current_pin))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                if (SecurityHelper.verifyPin(this, input.text.toString())) {
                    SecurityHelper.clearPin(this)
                    Toast.makeText(this, getString(R.string.security_pin_disabled), Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, getString(R.string.security_pin_mismatch), Toast.LENGTH_LONG).show()
                }
                refreshUi()
            }
            .setNegativeButton(getString(R.string.dialog_close)) { _, _ -> refreshUi() }
            .setOnCancelListener { refreshUi() }
            .show()
    }

    private fun promptChangePin() {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_disable_pin_title))
            .setMessage(getString(R.string.security_enter_current_pin))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                if (SecurityHelper.verifyPin(this, input.text.toString())) {
                    promptSetNewPin()
                } else {
                    Toast.makeText(this, getString(R.string.security_pin_mismatch), Toast.LENGTH_LONG).show()
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
EOF_SETTINGSSECURITYACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/SettingsSecurityActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/PitPersonalData.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/PitPersonalData.kt" << 'EOF_PITPERSONALDATA_KT'
package com.example.fa_ksiegowy

import android.content.Context

/**
 * Личные данные, нужные, чтобы правильно заполнить PIT-36 (имя/фамилия,
 * адрес, urząd skarbowy) и базовые данные для льгот (PIT/O). Хранится
 * локально в SharedPreferences — как и остальные настройки приложения.
 * Ничего не отправляется никуда за пределы устройства.
 */
data class PitPersonalData(
    val firstName: String = "",
    val lastName: String = "",
    val pesel: String = "",
    val street: String = "",
    val postalCode: String = "",
    val city: String = "",
    val taxOffice: String = "",
    val childrenCount: Int = 0,
    val internetRelief: Double = 0.0,
    val ikzeContribution: Double = 0.0,
    val donations: Double = 0.0,
    val jointWithSpouse: Boolean = false
) {
    val isComplete: Boolean
        get() = firstName.isNotBlank() && lastName.isNotBlank() && taxOffice.isNotBlank()
}

object PitDataStore {
    private const val PREFS = "pit_data"

    fun load(context: Context): PitPersonalData {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return PitPersonalData(
            firstName = p.getString("firstName", "") ?: "",
            lastName = p.getString("lastName", "") ?: "",
            pesel = p.getString("pesel", "") ?: "",
            street = p.getString("street", "") ?: "",
            postalCode = p.getString("postalCode", "") ?: "",
            city = p.getString("city", "") ?: "",
            taxOffice = p.getString("taxOffice", "") ?: "",
            childrenCount = p.getInt("childrenCount", 0),
            internetRelief = p.getFloat("internetRelief", 0f).toDouble(),
            ikzeContribution = p.getFloat("ikzeContribution", 0f).toDouble(),
            donations = p.getFloat("donations", 0f).toDouble(),
            jointWithSpouse = p.getBoolean("jointWithSpouse", false)
        )
    }

    fun save(context: Context, data: PitPersonalData) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("firstName", data.firstName)
            .putString("lastName", data.lastName)
            .putString("pesel", data.pesel)
            .putString("street", data.street)
            .putString("postalCode", data.postalCode)
            .putString("city", data.city)
            .putString("taxOffice", data.taxOffice)
            .putInt("childrenCount", data.childrenCount)
            .putFloat("internetRelief", data.internetRelief.toFloat())
            .putFloat("ikzeContribution", data.ikzeContribution.toFloat())
            .putFloat("donations", data.donations.toFloat())
            .putBoolean("jointWithSpouse", data.jointWithSpouse)
            .apply()
    }
}
EOF_PITPERSONALDATA_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/PitPersonalData.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/Pit36Calculator.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/Pit36Calculator.kt" << 'EOF_PIT36CALCULATOR_KT'
package com.example.fa_ksiegowy

/**
 * Считает итоговые цифры для PIT-36 по данным за один календарный год:
 * Przychód (сумма всех доходов), Koszty (сумма всех расходов), Dochód (разница),
 * и налог, относящийся именно к прибыли из приложения — той же маржинальной
 * логикой, что уже используется на главном экране (см. TaxHelper).
 *
 * Это НЕ официальный расчёт налоговой — только вспомогательная оценка на основе
 * введённых пользователем данных, чтобы не считать вручную перед подачей PIT-36.
 */
object Pit36Calculator {

    data class Result(
        val year: Int,
        val przychod: Double,
        val koszty: Double,
        val dochod: Double,
        val otherIncome: Double,
        val tax: TaxHelper.TaxResult
    )

    fun calculate(entries: List<Entry>, year: Int, otherIncome: Double): Result {
        val przychod = entries.filter { it.isIncome }.sumOf { it.amount }
        val koszty = entries.filter { !it.isIncome }.sumOf { it.amount }
        val dochod = przychod - koszty
        val tax = TaxHelper.calc(dochod, otherIncome)
        return Result(year, przychod, koszty, dochod, otherIncome, tax)
    }
}
EOF_PIT36CALCULATOR_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/Pit36Calculator.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/Pit36PdfGenerator.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/Pit36PdfGenerator.kt" << 'EOF_PIT36PDFGENERATOR_KT'
package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Строит PDF-"шпаргалку" для заполнения PIT-36 за выбранный год: личные данные,
 * itogovые Przychód/Koszty/Dochód, расчёт налога и подсказки, в какую строку/раздел
 * официального бланка PIT-36 их перенести.
 *
 * ВАЖНО: это НЕ сам официальный бланк PIT-36 и не готовая e-Deklaracja — номера
 * конкретных клеток бланка каждый год может менять Minister Finansów, поэтому
 * вместо "впишите в поле №105" тут используются названия раздела/строки бланка,
 * которые более стабильны из года в год. Отчёт исключительно информационный
 * (см. дисклеймер в конце документа).
 */
object Pit36PdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    fun generate(context: Context, personal: PitPersonalData, result: Pit36Calculator.Result, out: OutputStream) {
        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas
        var y = MARGIN

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 18f; typeface = Typeface.DEFAULT_BOLD }
        val headerPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD }
        val textPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11f }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9.5f }
        val lineGap = 16f

        fun newPageIfNeeded(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) {
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
            }
        }

        fun line(text: String, paint: Paint = textPaint, gap: Float = lineGap) {
            newPageIfNeeded(gap)
            canvas.drawText(text, MARGIN, y, paint)
            y += gap
        }

        fun wrappedLines(text: String, maxCharsPerLine: Int = 92, paint: Paint = hintPaint, gap: Float = 13f) {
            val words = text.split(" ")
            var current = StringBuilder()
            for (w in words) {
                if (current.length + w.length + 1 > maxCharsPerLine) {
                    line(current.toString(), paint, gap)
                    current = StringBuilder()
                }
                if (current.isNotEmpty()) current.append(" ")
                current.append(w)
            }
            if (current.isNotEmpty()) line(current.toString(), paint, gap)
        }

        val money: (Double) -> String = {
            String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł"
        }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())

        line("FinArs — dane pomocnicze do PIT-36 za ${result.year} r.", titlePaint, 26f)
        line("Wygenerowano: ${dateFmt.format(Date())}", hintPaint, 20f)

        line("Dane podatnika", headerPaint, 20f)
        line("Imię i nazwisko: ${personal.firstName} ${personal.lastName}".trim())
        if (personal.pesel.isNotBlank()) line("PESEL: ${personal.pesel}")
        line("Adres: ${personal.street}, ${personal.postalCode} ${personal.city}".trim(' ', ','))
        line("Właściwy urząd skarbowy: ${personal.taxOffice}")
        line("Sposób rozliczenia: " + if (personal.jointWithSpouse) "Wspólnie z małżonkiem" else "Indywidualnie")
        y += 8f

        line("Działalność nierejestrowana — sekcja E.1 (Inne źródła)", headerPaint, 20f)
        wrappedLines("Wiersz: „Działalność nierejestrowana, określona w art. 20 ust. 1ba ustawy”.")
        y += 4f
        line("Przychód (kolumna „Przychód”):  ${money(result.przychod)}")
        line("Koszty uzyskania przychodów (kolumna „Koszty uzyskania przychodów”):  ${money(result.koszty)}")
        line("Dochód (kolumna „Dochód”, = Przychód − Koszty):  ${money(result.dochod)}")
        y += 8f

        line("Inne dochody i podatek", headerPaint, 20f)
        if (result.otherIncome > 0) {
            line("Inne dochody podane w ustawieniach (np. PIT-11 z etatu): ${money(result.otherIncome)}")
        }
        line("Łączny dochód do opodatkowania: ${money(result.tax.totalTaxable)}")
        wrappedLines("Skala podatkowa: 0% do 30 000 zł, 12% od nadwyżki ponad 30 000 zł do 120 000 zł, 32% od nadwyżki ponad 120 000 zł.")
        line("Podatek przypadający na dochód z tej aplikacji (szacunkowo): ${money(result.tax.tax)}")
        y += 8f

        if (personal.childrenCount > 0 || personal.internetRelief > 0 || personal.ikzeContribution > 0 || personal.donations > 0) {
            line("Ulgi i odliczenia (załącznik PIT/O) — do weryfikacji z aktualnymi limitami", headerPaint, 20f)
            if (personal.childrenCount > 0) line("Liczba dzieci uprawniających do ulgi: ${personal.childrenCount}")
            if (personal.internetRelief > 0) line("Ulga internetowa (poniesiony wydatek): ${money(personal.internetRelief)}")
            if (personal.ikzeContribution > 0) line("Wpłaty na IKZE: ${money(personal.ikzeContribution)}")
            if (personal.donations > 0) line("Darowizny: ${money(personal.donations)}")
            wrappedLines("Kwoty te wpisuje się w załączniku PIT/O do PIT-36 — aplikacja nie pomniejsza automatycznie podatku o te ulgi, ponieważ każda z nich ma własne roczne limity i warunki.")
            y += 8f
        }

        newPageIfNeeded(90f)
        line("Ważne informacje", headerPaint, 20f)
        wrappedLines("• Przychód liczony jest metodą memoriałową (data sprzedaży/wykonania usługi), a Koszty metodą kasową (data faktycznej zapłaty) — zgodnie z zasadami działalności nierejestrowanej.")
        wrappedLines("• Jeśli w ciągu roku otrzymałeś(-aś) PIT-11 (np. z umowy o pracę), dochody z niego należy dodać do PIT-36 ręcznie lub przez kreator w portalu Twój e-PIT — ta aplikacja ich nie zawiera, chyba że zostały wpisane jako „Inne przychody” w ustawieniach.")
        wrappedLines("• Dokument ten nie jest oficjalnym formularzem PIT-36 ani e-Deklaracją — to wyłącznie pomocnicze zestawienie liczb do ręcznego przepisania na portalu podatki.gov.pl (Twój e-PIT) lub do papierowego formularza.")
        y += 6f
        wrappedLines("Aplikacja FinArs ma charakter pomocniczy i nie stanowi oficjalnej porady księgowej ani podatkowej. W razie wątpliwości skonsultuj się z doradcą podatkowym lub urzędem skarbowym.", 92, hintPaint, 13f)

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}
EOF_PIT36PDFGENERATOR_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/Pit36PdfGenerator.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/PitDataActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/PitDataActivity.kt" << 'EOF_PITDATAACTIVITY_KT'
package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.Toast

/** Форма личных данных, нужных для отчёта PIT-36 (см. Pit36PdfGenerator). */
class PitDataActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pit_data)

        val data = PitDataStore.load(this)
        findViewById<EditText>(R.id.et_first_name).setText(data.firstName)
        findViewById<EditText>(R.id.et_last_name).setText(data.lastName)
        findViewById<EditText>(R.id.et_pesel).setText(data.pesel)
        findViewById<EditText>(R.id.et_street).setText(data.street)
        findViewById<EditText>(R.id.et_postal_code).setText(data.postalCode)
        findViewById<EditText>(R.id.et_city).setText(data.city)
        findViewById<EditText>(R.id.et_tax_office).setText(data.taxOffice)
        findViewById<EditText>(R.id.et_children_count).setText(if (data.childrenCount > 0) data.childrenCount.toString() else "")
        findViewById<EditText>(R.id.et_internet_relief).setText(if (data.internetRelief > 0) data.internetRelief.toString() else "")
        findViewById<EditText>(R.id.et_ikze).setText(if (data.ikzeContribution > 0) data.ikzeContribution.toString() else "")
        findViewById<EditText>(R.id.et_donations).setText(if (data.donations > 0) data.donations.toString() else "")
        findViewById<CheckBox>(R.id.cb_joint_spouse).isChecked = data.jointWithSpouse

        findViewById<Button>(R.id.btn_save_pit_data).setOnClickListener { save() }
    }

    private fun save() {
        fun text(id: Int) = findViewById<EditText>(id).text.toString().trim()
        fun number(id: Int) = text(id).replace(",", ".").toDoubleOrNull() ?: 0.0
        fun intNumber(id: Int) = text(id).toIntOrNull() ?: 0

        val firstName = text(R.id.et_first_name)
        val lastName = text(R.id.et_last_name)
        val taxOffice = text(R.id.et_tax_office)

        if (firstName.isBlank() || lastName.isBlank() || taxOffice.isBlank()) {
            Toast.makeText(this, getString(R.string.pit_data_required_error), Toast.LENGTH_LONG).show()
            return
        }

        val data = PitPersonalData(
            firstName = firstName,
            lastName = lastName,
            pesel = text(R.id.et_pesel),
            street = text(R.id.et_street),
            postalCode = text(R.id.et_postal_code),
            city = text(R.id.et_city),
            taxOffice = taxOffice,
            childrenCount = intNumber(R.id.et_children_count),
            internetRelief = number(R.id.et_internet_relief),
            ikzeContribution = number(R.id.et_ikze),
            donations = number(R.id.et_donations),
            jointWithSpouse = findViewById<CheckBox>(R.id.cb_joint_spouse).isChecked
        )
        PitDataStore.save(this, data)
        Toast.makeText(this, getString(R.string.saved), Toast.LENGTH_SHORT).show()
        finish()
    }
}
EOF_PITDATAACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/PitDataActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt" << 'EOF_PIT36ACTIVITY_KT'
package com.example.fa_ksiegowy

import android.net.Uri
import android.os.Bundle
import android.widget.Button
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
 */
class Pit36Activity : BaseActivity() {

    private var selectedYear = Calendar.getInstance().get(Calendar.YEAR) - 1
    private var lastResult: Pit36Calculator.Result? = null

    private val createPdfLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        if (uri != null) writePdfTo(uri)
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
        findViewById<Button>(R.id.btn_generate_pit36).setOnClickListener { generateClicked() }

        refreshYearLabel()
    }

    override fun onResume() {
        super.onResume()
        recalculate()
    }

    private fun refreshYearLabel() {
        findViewById<TextView>(R.id.tv_pit_year).text = selectedYear.toString()
    }

    private fun recalculate() {
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val otherIncome = TaxHelper.getOtherIncome(prefs, selectedYear)
        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val (start, endExclusive) = TaxHelper.yearRange(selectedYear)
            val entries = db.entryDao().getBetween(start, endExclusive - 1)
            val result = Pit36Calculator.calculate(entries, selectedYear, otherIncome)
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

        val data = PitDataStore.load(this)
        findViewById<TextView>(R.id.tv_pit_data_status).text = if (data.isComplete) {
            getString(R.string.pit_data_status_ready, "${data.firstName} ${data.lastName}".trim())
        } else {
            getString(R.string.pit_data_status_missing)
        }
    }

    private fun generateClicked() {
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
        val dateForName = SimpleDateFormat("yyyyMMdd_HHmm", Locale.US).format(Date())
        createPdfLauncher.launch("PIT-36_pomocniczy_${selectedYear}_$dateForName.pdf")
    }

    private fun writePdfTo(uri: Uri) {
        val data = PitDataStore.load(this)
        val result = lastResult ?: return
        CoroutineScope(Dispatchers.IO).launch {
            try {
                contentResolver.openOutputStream(uri)?.use { out ->
                    Pit36PdfGenerator.generate(this@Pit36Activity, data, result, out)
                } ?: throw java.io.IOException("openOutputStream returned null")
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@Pit36Activity, getString(R.string.pit36_generated), Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@Pit36Activity, getString(R.string.report_error, e.message ?: ""), Toast.LENGTH_LONG).show()
                }
            }
        }
    }
}
EOF_PIT36ACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt"

mkdir -p "$(dirname "app/src/main/res/layout/activity_lock.xml")"
cat > "app/src/main/res/layout/activity_lock.xml" << 'EOF_ACTIVITY_LOCK_XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical"
    android:gravity="center_horizontal"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:background="@drawable/bg_gradient"
    android:padding="32dp">

    <ImageView android:id="@+id/iv_lock_logo"
        android:layout_width="96dp" android:layout_height="96dp"
        android:layout_marginTop="64dp" android:layout_marginBottom="20dp"/>

    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:text="@string/lock_title" android:textSize="20sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="8dp"/>

    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:text="@string/lock_subtitle" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="28dp"/>

    <EditText android:id="@+id/et_pin"
        android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/input_field_bg"
        android:paddingStart="18dp" android:paddingEnd="18dp"
        android:hint="@string/lock_pin_hint"
        android:textColor="@color/text_primary" android:textColorHint="@color/text_hint"
        android:inputType="numberPassword" android:maxLength="6"
        android:gravity="center" android:textSize="22sp" android:letterSpacing="0.4"
        android:imeOptions="actionDone"
        android:layout_marginBottom="10dp"/>

    <TextView android:id="@+id/tv_lock_error"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/lock_wrong_pin" android:textColor="@color/expense_red"
        android:textSize="13sp" android:gravity="center" android:visibility="gone"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_unlock"
        android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/lock_unlock_button" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_use_biometric"
        android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/lock_biometric_button" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:visibility="gone"/>

</LinearLayout>
EOF_ACTIVITY_LOCK_XML
echo "OK: app/src/main/res/layout/activity_lock.xml"

mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_security.xml")"
cat > "app/src/main/res/layout/activity_settings_security.xml" << 'EOF_ACTIVITY_SETTINGS_SECURITY_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/settings_menu_security" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="16dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/security_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="20dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="center_vertical"
        android:background="@drawable/card_bg" android:padding="16dp" android:layout_marginBottom="12dp">
        <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
            android:text="@string/security_pin_switch" android:textSize="15sp" android:textColor="@color/text_primary"/>
        <Switch android:id="@+id/switch_pin" android:layout_width="wrap_content" android:layout_height="wrap_content"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_change_pin" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/security_change_pin" android:textSize="14sp" android:textColor="@color/accent_cyan"
        android:padding="8dp" android:layout_marginBottom="12dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="center_vertical"
        android:background="@drawable/card_bg" android:padding="16dp" android:layout_marginBottom="12dp">
        <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
            android:text="@string/security_biometric_switch" android:textSize="15sp" android:textColor="@color/text_primary"/>
        <Switch android:id="@+id/switch_biometric" android:layout_width="wrap_content" android:layout_height="wrap_content"/>
    </LinearLayout>

</LinearLayout>
</ScrollView>
EOF_ACTIVITY_SETTINGS_SECURITY_XML
echo "OK: app/src/main/res/layout/activity_settings_security.xml"

mkdir -p "$(dirname "app/src/main/res/layout/activity_pit_data.xml")"
cat > "app/src/main/res/layout/activity_pit_data.xml" << 'EOF_ACTIVITY_PIT_DATA_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_data_title" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="6dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_data_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="18dp"/>

    <EditText android:id="@+id/et_first_name" style="@style/PitInput" android:hint="@string/pit_first_name"/>
    <EditText android:id="@+id/et_last_name" style="@style/PitInput" android:hint="@string/pit_last_name"/>
    <EditText android:id="@+id/et_pesel" style="@style/PitInput" android:hint="@string/pit_pesel"
        android:inputType="number" android:maxLength="11"/>
    <EditText android:id="@+id/et_street" style="@style/PitInput" android:hint="@string/pit_street"/>
    <EditText android:id="@+id/et_postal_code" style="@style/PitInput" android:hint="@string/pit_postal_code"/>
    <EditText android:id="@+id/et_city" style="@style/PitInput" android:hint="@string/pit_city"/>
    <EditText android:id="@+id/et_tax_office" style="@style/PitInput" android:hint="@string/pit_tax_office"/>

    <View android:layout_width="match_parent" android:layout_height="1dp"
        android:background="#2A2E60" android:layout_marginTop="6dp" android:layout_marginBottom="18dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_reliefs_title" android:textSize="15sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="12dp"/>

    <EditText android:id="@+id/et_children_count" style="@style/PitInput" android:hint="@string/pit_children_count"
        android:inputType="number"/>
    <EditText android:id="@+id/et_internet_relief" style="@style/PitInput" android:hint="@string/pit_internet_relief"
        android:inputType="numberDecimal"/>
    <EditText android:id="@+id/et_ikze" style="@style/PitInput" android:hint="@string/pit_ikze"
        android:inputType="numberDecimal"/>
    <EditText android:id="@+id/et_donations" style="@style/PitInput" android:hint="@string/pit_donations"
        android:inputType="numberDecimal"/>

    <CheckBox android:id="@+id/cb_joint_spouse" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_joint_spouse" android:textColor="@color/text_primary"
        android:layout_marginBottom="20dp"/>

    <Button android:id="@+id/btn_save_pit_data" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/save" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>

</LinearLayout>
</ScrollView>
EOF_ACTIVITY_PIT_DATA_XML
echo "OK: app/src/main/res/layout/activity_pit_data.xml"

mkdir -p "$(dirname "app/src/main/res/layout/activity_pit36.xml")"
cat > "app/src/main/res/layout/activity_pit36.xml" << 'EOF_ACTIVITY_PIT36_XML'
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
        android:layout_marginBottom="14dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit36_disclaimer" android:textSize="11sp"
        android:textColor="@color/text_hint"/>

</LinearLayout>
</ScrollView>
EOF_ACTIVITY_PIT36_XML
echo "OK: app/src/main/res/layout/activity_pit36.xml"

echo "--- 3/4: обновлённые файлы (перезаписываются полностью) ---"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/FaApp.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/FaApp.kt" << 'EOF_FAAPP_KT'
package com.example.fa_ksiegowy

import android.app.Activity
import android.app.Application
import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Application-класс: ставит глобальный обработчик необработанных исключений.
 * Сохраняет полный текст краша (стектрейс) в файл в папке "Загрузки"
 * (finars_crash_ГГГГММДД_ЧЧММСС.txt), чтобы его можно было прочитать через
 * Termux (cat /storage/emulated/0/Download/finars_crash_*.txt) — обычный
 * logcat не показывает логи чужого приложения без прав root.
 *
 * После записи лога вызывается стандартный обработчик системы — поведение
 * приложения при краше (закрытие) не меняется, только добавляется файл.
 */
class FaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                saveCrashLog(this, throwable)
            } catch (e: Throwable) {
                // Если даже запись лога не удалась — не мешаем системному обработчику
            }
            defaultHandler?.uncaughtException(thread, throwable)
        }

        // Отслеживаем переход приложения на передний план/в фон для блокировки по PIN.
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) {
                AppLockState.onActivityStarted(activity)
            }
            override fun onActivityStopped(activity: Activity) {
                AppLockState.onActivityStopped()
            }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    private fun saveCrashLog(context: Context, throwable: Throwable) {
        val sw = StringWriter()
        throwable.printStackTrace(PrintWriter(sw))
        val text = "FinArs crash log\n" +
            SimpleDateFormat("dd.MM.yyyy HH:mm:ss", Locale.US).format(Date()) + "\n\n" +
            sw.toString()
        val fileName = "finars_crash_" +
            SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".txt"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) }
            }
        } else {
            @Suppress("DEPRECATION")
            val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            downloads.mkdirs()
            val file = File(downloads, fileName)
            FileOutputStream(file).use { it.write(text.toByteArray()) }
        }
    }
}
EOF_FAAPP_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/FaApp.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/BaseActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/BaseActivity.kt" << 'EOF_BASEACTIVITY_KT'
package com.example.fa_ksiegowy

import android.content.Context
import android.content.Intent
import androidx.appcompat.app.AppCompatActivity

open class BaseActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleHelper.applyLocale(newBase))
    }

    /** Показываем экран блокировки поверх любого экрана приложения, если
     *  AppLockState считает, что приложение только что вернулось из фона
     *  и PIN установлен. Сам LockActivity этот код у себя не выполняет
     *  (иначе он бесконечно запускал бы сам себя). */
    override fun onResume() {
        super.onResume()
        if (this !is LockActivity && AppLockState.isLocked) {
            startActivity(Intent(this, LockActivity::class.java))
        }
    }
}
EOF_BASEACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/BaseActivity.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt" << 'EOF_SETTINGSACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button

/** Главное меню настроек — теперь просто категории, сами экраны вынесены
 *  в отдельные Activity, чтобы список не занимал весь экран и было место
 *  под будущие разделы. */
class SettingsActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        findViewById<Button>(R.id.btn_menu_tax).setOnClickListener {
            startActivity(Intent(this, SettingsTaxActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_language).setOnClickListener {
            startActivity(Intent(this, SettingsLanguageActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_security).setOnClickListener {
            startActivity(Intent(this, SettingsSecurityActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_pit36).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, Pit36Activity::class.java))
            } else {
                AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.pit36_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(this, SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        findViewById<Button>(R.id.btn_menu_backup).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, SettingsBackupActivity::class.java))
            } else {
                AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.backup_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(this, SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        findViewById<Button>(R.id.btn_menu_pro).setOnClickListener {
            startActivity(Intent(this, SettingsProActivity::class.java))
        }
        findViewById<Button>(R.id.btn_menu_about).setOnClickListener {
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.about_app))
                .setMessage(getString(R.string.about_description))
                .setPositiveButton(getString(R.string.dialog_write)) { _, _ ->
                    val intent = Intent(Intent.ACTION_SENDTO).apply {
                        data = Uri.parse("mailto:" + getString(R.string.about_email))
                    }
                    startActivity(intent)
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }
    }
}
EOF_SETTINGSACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt"

mkdir -p "$(dirname "app/src/main/res/layout/activity_settings.xml")"
cat > "app/src/main/res/layout/activity_settings.xml" << 'EOF_ACTIVITY_SETTINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:padding="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/settings" android:textSize="22sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="24dp"/>

    <Button android:id="@+id/btn_menu_tax" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_tax" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_language" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_language" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_security" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_security" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_backup" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_backup" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_pit36" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_pit36" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_menu_pro" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/settings_menu_pro" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
        android:layout_marginBottom="14dp"/>

    <View android:layout_width="match_parent" android:layout_height="1dp"
        android:background="#2A2E60" android:layout_marginTop="10dp" android:layout_marginBottom="24dp"/>

    <Button android:id="@+id/btn_menu_about" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/about_app" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>

</LinearLayout>
</ScrollView>
EOF_ACTIVITY_SETTINGS_XML
echo "OK: app/src/main/res/layout/activity_settings.xml"

mkdir -p "$(dirname "app/src/main/res/values/themes.xml")"
cat > "app/src/main/res/values/themes.xml" << 'EOF_THEMES_XML'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.FA" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="colorPrimary">@color/accent_blue_light</item>
        <item name="colorPrimaryVariant">@color/accent_blue_dark</item>
        <item name="colorOnPrimary">@color/text_primary</item>
        <item name="colorSecondary">@color/accent_cyan</item>
        <item name="colorSecondaryVariant">@color/accent_blue_dark</item>
        <item name="colorOnSecondary">@color/text_primary</item>
        <item name="android:statusBarColor">@color/bg_top</item>
        <item name="android:windowBackground">@drawable/bg_gradient</item>
        <item name="android:textColorPrimary">@color/text_primary</item>
        <item name="android:textColorHint">@color/text_hint</item>
    </style>

    <style name="PitInput">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">56dp</item>
        <item name="android:background">@drawable/input_field_bg</item>
        <item name="android:paddingStart">18dp</item>
        <item name="android:paddingEnd">18dp</item>
        <item name="android:textColor">@color/text_primary</item>
        <item name="android:textColorHint">@color/text_hint</item>
        <item name="android:layout_marginBottom">12dp</item>
    </style>
</resources>
EOF_THEMES_XML
echo "OK: app/src/main/res/values/themes.xml"

mkdir -p "$(dirname "app/src/main/res/values/strings.xml")"
cat > "app/src/main/res/values/strings.xml" << 'EOF_STRINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Add income</string>
    <string name="add_expense">Add expense</string>
    <string name="add_entry">Add +</string>
    <string name="balance">Balance</string>
    <string name="enter_amount">Amount</string>
    <string name="enter_comment">Comment</string>
    <string name="attach_receipt">Attach receipt</string>
    <string name="save">Save</string>
    <string name="settings">Settings</string>
    <string name="tax_percent">Tax percent</string>
    <string name="other_income_label">Other income (%1$d)</string>
    <string name="tax_scale_title">Tax is calculated automatically</string>
    <string name="tax_scale_description" formatted="false">0% up to 30,000 zł/year · 12% on the part between 30,000 and 120,000 zł · 32% on the part above 120,000 zł. The rate applies only to the amount above each threshold, not to the whole sum.</string>
    <string name="other_income_title">Other income</string>
    <string name="other_income_hint">Your total taxable income this year from other sources (job, other business, etc.). Used together with income from this app to check the 30,000 zł annual tax-free limit.</string>
    <string name="saved">Saved</string>
    <string name="auto_tax_button">Calculate automatically</string>
    <string name="auto_tax_result">Suggested rate: %1$.1f%% (based on Polish PIT scale: 12%% up to 120,000 zł/year, 32%% above). You can edit it before saving.</string>
    <string name="export_report">Export report</string>
    <string name="generate_report">Generate report</string>
    <string name="select_period">Select period</string>
    <string name="month">Month</string>
    <string name="year">Year</string>
    <string name="custom_range">Custom range</string>
    <string name="from">From</string>
    <string name="to">To</string>
    <string name="no_entries">No entries</string>

    <string name="statistics">Statistics</string>
    <string name="stat_income">Income</string>
    <string name="stat_expense">Expense</string>
    <string name="stat_profit">Profit (gross)</string>
    <string name="stat_tax_format">Tax (%1$.1f%%)</string>

    <string name="report_col_date">Date</string>
    <string name="report_col_income">Income</string>
    <string name="report_col_expense">Expense</string>
    <string name="report_col_tax_percent">Tax %%</string>
    <string name="report_col_tax_amount">Tax amount</string>
    <string name="report_col_comment">Comment</string>
    <string name="report_sheet_name">Report</string>
    <string name="report_title_month">Report — Month</string>
    <string name="report_title_year">Report — Year</string>
    <string name="report_title_custom">Report — Custom period</string>
    <string name="custom_range_invalid">The end date must be after the start date</string>
    <string name="report_total_income">Total income</string>
    <string name="report_total_expense">Total expense</string>
    <string name="report_total_profit">Total profit</string>
    <string name="report_total_tax">Total tax</string>
    <string name="report_total_net_profit">Net profit (after tax)</string>
    <string name="report_generating">Generating report…</string>
    <string name="report_ready">Report ready</string>
    <string name="report_share_title">Share report</string>
    <string name="report_error">Failed to generate report: %1$s</string>
    <string name="about_app">About the app</string>
    <string name="about_description">FinArs is a convenient app for managing the finances of unregistered business activity. Easily track income and expenses, monitor your current balance, automatically calculate taxes and generate reports. The app helps you stay within limits, track financial indicators and always have the full history of operations at hand. A simple interface and quick data entry make daily bookkeeping as convenient as possible.

Key features:
💰 Income and expense tracking.
📊 Automatic profit calculation.
🧾 Tax calculation.
📈 Monitoring of unregistered activity limits.
📄 Report generation.
🔍 Full operation history.
🌙 Modern dark interface.
🔒 All data is stored locally on the device.

Contact: p.arsenii@interia.pl</string>
    <string name="about_email">p.arsenii@interia.pl</string>
    <string name="dialog_close">Close</string>
    <string name="dialog_write">Write</string>
    <string name="pro_status_locked">Pro is locked. Unlock to get yearly/custom Excel reports, backup \&amp; restore, and remove ads.</string>
    <string name="pro_status_active">Pro unlocked. Thank you for your support!</string>
    <string name="pro_unlock_button">Unlock Pro</string>
    <string name="pro_unlock_button_price">Unlock Pro — %1$s</string>
    <string name="pro_loading">Loading price…</string>
    <string name="pro_feature_locked_title">Pro feature</string>
    <string name="pro_feature_locked_message">Yearly and custom reports are a Pro feature. Unlock Pro in Settings to use them.</string>
    <string name="pro_feature_locked_go_settings">Go to Settings</string>
    <string name="backup_pro_locked_message">Backup and restore is a Pro feature. Unlock Pro to keep your data safe with a backup file.</string>
    <string name="pro_purchase_error">Could not start the purchase. Check your connection and try again.</string>
    <string name="pro_info_title">Pro version</string>
    <string name="pro_info_message">Pro unlocks:\n\n• Yearly Excel report\n• Custom-period Excel report\n• Backup \&amp; restore\n• No ads\n\nThis is a one-time purchase — pay once, keep it forever.</string>
    <string name="pro_info_continue">Continue to purchase</string>
    <string name="enter_code_button">Have a code?</string>
    <string name="enter_code_title">Enter code</string>
    <string name="enter_code_hint">Code</string>
    <string name="enter_code_apply">Apply</string>
    <string name="enter_code_wrong">Invalid code</string>
    <string name="enter_code_success">Pro unlocked</string>
    <string name="transaction_history">Transaction history</string>
    <string name="stat_net_profit">Net profit (after tax)</string>
    <string name="type_income">Income</string>
    <string name="type_expense">Expense</string>
    <string name="edit_income_title">Edit income</string>
    <string name="edit_expense_title">Edit expense</string>
    <string name="delete_entry">Delete</string>
    <string name="delete_confirm_title">Delete entry?</string>
    <string name="delete_confirm_message">This entry will be permanently deleted. This cannot be undone.</string>
    <string name="delete_confirm_yes">Delete</string>
    <string name="entry_updated">Updated</string>
    <string name="entry_deleted">Deleted</string>
    <string name="clear_all_button">Clear all data</string>
    <string name="clear_all_confirm_title">Are you sure?</string>
    <string name="clear_all_confirm_message">All income and expense entries will be permanently deleted. This cannot be undone.</string>
    <string name="clear_all_confirm_yes">Delete all</string>
    <string name="clear_all_done">All data has been deleted</string>

    <string name="settings_menu_tax">Tax and limits</string>
    <string name="settings_menu_language">Language</string>
    <string name="settings_menu_backup">Backup (Pro)</string>
    <string name="settings_menu_pro">Pro version</string>

    <string name="backup_hint">Save a backup of your income/expense entries — including amounts, dates, comments and attached receipt photos — as a file. In the save dialog you can choose phone storage or Google Drive (if the Drive app is installed). Keep this file safe: it\'s the only way to restore your data if you lose the phone or reinstall the app.</string>
    <string name="backup_in_progress">Working…</string>
    <string name="backup_create">Create backup</string>
    <string name="backup_restore">Restore from backup</string>
    <string name="backup_success">Backup saved (%1$d entries)</string>
    <string name="backup_error">Error: %1$s</string>
    <string name="backup_restore_confirm_title">Restore from backup?</string>
    <string name="backup_restore_confirm_message">Entries from the backup file will be added to what you already have on this device (existing entries are not deleted or overwritten). If you want a clean restore, use \"Clear all data\" first, then restore.</string>
    <string name="backup_invalid_file">This does not look like a valid FinArs backup file</string>
    <string name="backup_restored">Restored %1$d entries</string>
    <string name="backup_never">Last backup: never</string>
    <string name="backup_last_time">Last backup: %1$s</string>

    <string name="settings_menu_security">Security (PIN / fingerprint)</string>
    <string name="settings_menu_pit36">Generate PIT-36 (Pro)</string>
    <string name="pit36_pro_locked_message">PIT-36 generation is a Pro feature. Unlock Pro in Settings to use it.</string>

    <string name="lock_title">FinArs is locked</string>
    <string name="lock_subtitle">Enter your PIN to continue</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Wrong PIN, try again</string>
    <string name="lock_unlock_button">Unlock</string>
    <string name="lock_biometric_button">Use fingerprint / face</string>
    <string name="lock_biometric_prompt_title">Unlock FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Confirm your fingerprint or face</string>
    <string name="lock_use_pin">Use PIN</string>
    <string name="lock_biometric_unavailable">No fingerprint/face is set up on this device. Add one in your phone\'s settings first.</string>

    <string name="security_hint">Protect the app with a PIN code. When enabled, FinArs will ask for the PIN every time you open it after leaving the app. You can also enable fingerprint/face unlock as a quick shortcut for the same PIN.</string>
    <string name="security_pin_switch">Require PIN to open the app</string>
    <string name="security_change_pin">Change PIN</string>
    <string name="security_biometric_switch">Unlock with fingerprint / face</string>
    <string name="security_set_pin_title">Set a PIN</string>
    <string name="security_set_pin_message">Choose a 4–6 digit PIN</string>
    <string name="security_continue">Continue</string>
    <string name="security_pin_length_error">PIN must be 4–6 digits</string>
    <string name="security_confirm_pin_title">Confirm your PIN</string>
    <string name="security_pin_saved">PIN saved</string>
    <string name="security_pin_mismatch">PINs don\'t match, try again</string>
    <string name="security_disable_pin_title">Enter current PIN</string>
    <string name="security_enter_current_pin">Enter your current PIN to continue</string>
    <string name="security_pin_disabled">PIN protection disabled</string>

    <string name="pit_data_title">Personal data for PIT-36</string>
    <string name="pit_data_hint">Used only to fill in the PIT-36 helper report. Everything stays on your device.</string>
    <string name="pit_first_name">First name</string>
    <string name="pit_last_name">Last name</string>
    <string name="pit_pesel">PESEL (optional)</string>
    <string name="pit_street">Street and house/apartment number</string>
    <string name="pit_postal_code">Postal code</string>
    <string name="pit_city">City</string>
    <string name="pit_tax_office">Tax office (urząd skarbowy)</string>
    <string name="pit_reliefs_title">Reliefs and deductions (optional)</string>
    <string name="pit_children_count">Number of children (ulga na dzieci)</string>
    <string name="pit_internet_relief">Internet relief — amount spent</string>
    <string name="pit_ikze">IKZE contributions</string>
    <string name="pit_donations">Donations (darowizny)</string>
    <string name="pit_joint_spouse">File jointly with spouse</string>
    <string name="pit_data_required_error">Please fill in first name, last name and tax office first</string>

    <string name="pit36_hint">Pick a full calendar year, check your personal data, then generate a helper PDF with the numbers and guidance for filling in the official PIT-36 form on podatki.gov.pl (Twój e-PIT) or on paper.</string>
    <string name="pit_row_przychod">Przychód (income)</string>
    <string name="pit_row_koszty">Koszty (expenses)</string>
    <string name="pit_row_dochod">Dochód (profit)</string>
    <string name="pit_row_tax">Estimated tax</string>
    <string name="pit_data_status_missing">Personal data not filled in yet — required before generating the report.</string>
    <string name="pit_data_status_ready">Personal data ready: %1$s</string>
    <string name="pit_edit_data_button">Edit personal data</string>
    <string name="pit36_generate_button">Generate PIT-36 helper PDF</string>
    <string name="pit36_disclaimer">This report is informational only and is not an official PIT-36 form, e-Deklaracja or tax advice. Always double-check the numbers before submitting your declaration.</string>
    <string name="pit36_calculating">Still calculating, please wait…</string>
    <string name="pit36_generated">PDF report generated</string>
</resources>
EOF_STRINGS_XML
echo "OK: app/src/main/res/values/strings.xml"

mkdir -p "$(dirname "app/src/main/res/values-pl/strings.xml")"
cat > "app/src/main/res/values-pl/strings.xml" << 'EOF_STRINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Dodaj przychód</string>
    <string name="add_expense">Dodaj wydatek</string>
    <string name="add_entry">Dodaj +</string>
    <string name="balance">Bilans</string>
    <string name="enter_amount">Kwota</string>
    <string name="enter_comment">Komentarz</string>
    <string name="attach_receipt">Dołącz paragon</string>
    <string name="save">Zapisz</string>
    <string name="settings">Ustawienia</string>
    <string name="tax_percent">Procent podatku</string>
    <string name="other_income_label">Inne przychody (%1$d)</string>
    <string name="tax_scale_title">Podatek liczony jest automatycznie</string>
    <string name="tax_scale_description" formatted="false">0% do 30 000 zł/rok · 12% od kwoty od 30 000 do 120 000 zł · 32% od kwoty powyżej 120 000 zł. Stawka dotyczy tylko części ponad każdy próg, a nie całej kwoty.</string>
    <string name="other_income_title">Inne przychody</string>
    <string name="other_income_hint">Twój łączny dochód podlegający opodatkowaniu w tym roku z innych źródeł (etat, inna działalność itd.). Uwzględniany razem z dochodem z tej aplikacji przy sprawdzaniu rocznego limitu wolnego od podatku 30 000 zł.</string>
    <string name="saved">Zapisano</string>
    <string name="auto_tax_button">Oblicz automatycznie</string>
    <string name="auto_tax_result">Sugerowana stawka: %1$.1f%% (wg skali PIT: 12%% do 120 000 zł/rok, 32%% powyżej). Przed zapisaniem można poprawić ręcznie.</string>
    <string name="export_report">Eksportuj raport</string>
    <string name="generate_report">Generuj raport</string>
    <string name="select_period">Wybierz okres</string>
    <string name="month">Miesiąc</string>
    <string name="year">Rok</string>
    <string name="custom_range">Zakres niestandardowy</string>
    <string name="from">Od</string>
    <string name="to">Do</string>
    <string name="no_entries">Brak wpisów</string>

    <string name="statistics">Statystyka</string>
    <string name="stat_income">Przychód</string>
    <string name="stat_expense">Wydatek</string>
    <string name="stat_profit">Zysk (brutto)</string>
    <string name="stat_tax_format">Podatek (%1$.1f%%)</string>

    <string name="report_col_date">Data</string>
    <string name="report_col_income">Przychód</string>
    <string name="report_col_expense">Wydatek</string>
    <string name="report_col_tax_percent">Podatek %%</string>
    <string name="report_col_tax_amount">Kwota podatku</string>
    <string name="report_col_comment">Komentarz</string>
    <string name="report_sheet_name">Raport</string>
    <string name="report_title_month">Raport — Miesiąc</string>
    <string name="report_title_year">Raport — Rok</string>
    <string name="report_title_custom">Raport — Zakres niestandardowy</string>
    <string name="custom_range_invalid">Data końcowa musi być późniejsza niż data początkowa</string>
    <string name="report_total_income">Suma przychodów</string>
    <string name="report_total_expense">Suma wydatków</string>
    <string name="report_total_profit">Suma zysku</string>
    <string name="report_total_tax">Suma podatku</string>
    <string name="report_total_net_profit">Zysk netto (po podatku)</string>
    <string name="report_generating">Generuję raport…</string>
    <string name="report_ready">Raport gotowy</string>
    <string name="report_share_title">Udostępnij raport</string>
    <string name="report_error">Błąd generowania raportu: %1$s</string>
    <string name="about_app">O aplikacji</string>
    <string name="about_description">FinArs to wygodna aplikacja do zarządzania finansami działalności nierejestrowanej. Łatwo śledź przychody i wydatki, kontroluj bieżący bilans, automatycznie obliczaj podatki i generuj raporty. Aplikacja pomaga przestrzegać limitów, śledzić wskaźniki finansowe i mieć zawsze pod ręką pełną historię operacji. Prosty interfejs i szybkie wprowadzanie danych sprawiają, że codzienna księgowość jest maksymalnie wygodna.\n\nGłówne funkcje:\n💰 Ewidencja przychodów i wydatków.\n📊 Automatyczne obliczanie zysku.\n🧾 Obliczanie podatków.\n📈 Kontrola limitów działalności nierejestrowanej.\n📄 Generowanie raportów.\n🔍 Historia wszystkich operacji.\n🌙 Nowoczesny ciemny interfejs.\n🔒 Wszystkie dane są przechowywane lokalnie na urządzeniu.\n\nKontakt: p.arsenii@interia.pl</string>
    <string name="about_email">p.arsenii@interia.pl</string>
    <string name="dialog_close">Zamknij</string>
    <string name="dialog_write">Napisz</string>
    <string name="pro_status_locked">Pro jest zablokowane. Odblokuj, aby uzyskać roczne i niestandardowe raporty Excel, kopię zapasową i przywracanie danych oraz usunąć reklamy.</string>
    <string name="pro_status_active">Pro odblokowane. Dziękujemy za wsparcie!</string>
    <string name="pro_unlock_button">Odblokuj Pro</string>
    <string name="pro_unlock_button_price">Odblokuj Pro — %1$s</string>
    <string name="pro_loading">Ładowanie ceny…</string>
    <string name="pro_feature_locked_title">Funkcja Pro</string>
    <string name="pro_feature_locked_message">Raporty roczne i niestandardowe są dostępne tylko w wersji Pro. Odblokuj Pro w ustawieniach.</string>
    <string name="pro_feature_locked_go_settings">Przejdź do ustawień</string>
    <string name="backup_pro_locked_message">Kopia zapasowa i przywracanie to funkcja Pro. Odblokuj Pro, aby zabezpieczyć swoje dane plikiem kopii zapasowej.</string>
    <string name="pro_purchase_error">Nie udało się otworzyć zakupu. Sprawdź połączenie i spróbuj ponownie.</string>
    <string name="pro_info_title">Wersja Pro</string>
    <string name="pro_info_message">Pro odblokowuje:\n\n• Raport roczny w Excelu\n• Raport za dowolny okres\n• Kopia zapasowa i przywracanie danych\n• Brak reklam\n\nTo jednorazowy zakup — płacisz raz, dostęp zostaje na zawsze.</string>
    <string name="pro_info_continue">Przejdź do zakupu</string>
    <string name="enter_code_button">Masz kod?</string>
    <string name="enter_code_title">Wprowadź kod</string>
    <string name="enter_code_hint">Kod</string>
    <string name="enter_code_apply">Zastosuj</string>
    <string name="enter_code_wrong">Nieprawidłowy kod</string>
    <string name="enter_code_success">Pro odblokowane</string>
    <string name="transaction_history">Historia transakcji</string>
    <string name="stat_net_profit">Zysk netto (po podatku)</string>
    <string name="type_income">Przychód</string>
    <string name="type_expense">Wydatek</string>
    <string name="edit_income_title">Edytuj przychód</string>
    <string name="edit_expense_title">Edytuj wydatek</string>
    <string name="delete_entry">Usuń</string>
    <string name="delete_confirm_title">Usunąć wpis?</string>
    <string name="delete_confirm_message">Wpis zostanie trwale usunięty. Tej czynności nie można cofnąć.</string>
    <string name="delete_confirm_yes">Usuń</string>
    <string name="entry_updated">Zaktualizowano</string>
    <string name="entry_deleted">Usunięto</string>
    <string name="clear_all_button">Wyczyść wszystkie dane</string>
    <string name="clear_all_confirm_title">Na pewno?</string>
    <string name="clear_all_confirm_message">Wszystkie przychody i wydatki zostaną trwale usunięte. Tej czynności nie można cofnąć.</string>
    <string name="clear_all_confirm_yes">Usuń wszystko</string>
    <string name="clear_all_done">Wszystkie dane zostały usunięte</string>

    <string name="settings_menu_tax">Podatek i limity</string>
    <string name="settings_menu_language">Język</string>
    <string name="settings_menu_backup">Kopia zapasowa (Pro)</string>
    <string name="settings_menu_pro">Wersja Pro</string>

    <string name="backup_hint">Zapisz kopię zapasową przychodów/wydatków — kwoty, daty, komentarze i załączone zdjęcia paragonów — jako plik. W oknie zapisu możesz wybrać pamięć telefonu lub Dysk Google (jeśli aplikacja Dysku jest zainstalowana). Przechowuj ten plik w bezpiecznym miejscu — to jedyny sposób odzyskania danych w razie utraty telefonu lub reinstalacji aplikacji.</string>
    <string name="backup_in_progress">Trwa…</string>
    <string name="backup_create">Utwórz kopię zapasową</string>
    <string name="backup_restore">Przywróć z kopii</string>
    <string name="backup_success">Kopia zapisana (%1$d wpisów)</string>
    <string name="backup_error">Błąd: %1$s</string>
    <string name="backup_restore_confirm_title">Przywrócić z kopii?</string>
    <string name="backup_restore_confirm_message">Wpisy z pliku kopii zostaną dodane do tych, które już są na tym urządzeniu (istniejące wpisy nie są usuwane ani nadpisywane). Jeśli potrzebujesz "czystego" przywrócenia — najpierw użyj "Wyczyść wszystkie dane", a potem przywróć kopię.</string>
    <string name="backup_invalid_file">To nie wygląda na poprawny plik kopii zapasowej FinArs</string>
    <string name="backup_restored">Przywrócono wpisów: %1$d</string>
    <string name="backup_never">Ostatnia kopia: nigdy</string>
    <string name="backup_last_time">Ostatnia kopia: %1$s</string>

    <string name="settings_menu_security">Bezpieczeństwo (PIN / odcisk palca)</string>
    <string name="settings_menu_pit36">Generuj PIT-36 (Pro)</string>
    <string name="pit36_pro_locked_message">Generowanie PIT-36 to funkcja Pro. Odblokuj Pro w Ustawieniach, aby z niej skorzystać.</string>

    <string name="lock_title">FinArs jest zablokowany</string>
    <string name="lock_subtitle">Wpisz PIN, aby kontynuować</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Błędny PIN, spróbuj ponownie</string>
    <string name="lock_unlock_button">Odblokuj</string>
    <string name="lock_biometric_button">Użyj odcisku palca / twarzy</string>
    <string name="lock_biometric_prompt_title">Odblokuj FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Potwierdź odciskiem palca lub twarzą</string>
    <string name="lock_use_pin">Użyj PIN-u</string>
    <string name="lock_biometric_unavailable">Na tym urządzeniu nie skonfigurowano odcisku palca/twarzy. Dodaj go najpierw w ustawieniach telefonu.</string>

    <string name="security_hint">Zabezpiecz aplikację kodem PIN. Gdy funkcja jest włączona, FinArs poprosi o PIN za każdym razem, gdy wrócisz do aplikacji po jej opuszczeniu. Możesz też włączyć odblokowanie odciskiem palca/twarzą jako szybki skrót zamiast wpisywania tego samego PIN-u.</string>
    <string name="security_pin_switch">Wymagaj PIN-u przy otwieraniu aplikacji</string>
    <string name="security_change_pin">Zmień PIN</string>
    <string name="security_biometric_switch">Odblokowanie odciskiem palca / twarzą</string>
    <string name="security_set_pin_title">Ustaw PIN</string>
    <string name="security_set_pin_message">Wybierz PIN z 4–6 cyfr</string>
    <string name="security_continue">Dalej</string>
    <string name="security_pin_length_error">PIN musi mieć 4–6 cyfr</string>
    <string name="security_confirm_pin_title">Potwierdź PIN</string>
    <string name="security_pin_saved">PIN zapisany</string>
    <string name="security_pin_mismatch">PIN-y się nie zgadzają, spróbuj ponownie</string>
    <string name="security_disable_pin_title">Wpisz aktualny PIN</string>
    <string name="security_enter_current_pin">Wpisz aktualny PIN, aby kontynuować</string>
    <string name="security_pin_disabled">Ochrona PIN-em wyłączona</string>

    <string name="pit_data_title">Dane osobowe do PIT-36</string>
    <string name="pit_data_hint">Używane wyłącznie do wypełnienia pomocniczego raportu PIT-36. Wszystko zostaje na Twoim urządzeniu.</string>
    <string name="pit_first_name">Imię</string>
    <string name="pit_last_name">Nazwisko</string>
    <string name="pit_pesel">PESEL (opcjonalnie)</string>
    <string name="pit_street">Ulica i numer domu/mieszkania</string>
    <string name="pit_postal_code">Kod pocztowy</string>
    <string name="pit_city">Miejscowość</string>
    <string name="pit_tax_office">Urząd skarbowy</string>
    <string name="pit_reliefs_title">Ulgi i odliczenia (opcjonalnie)</string>
    <string name="pit_children_count">Liczba dzieci (ulga na dzieci)</string>
    <string name="pit_internet_relief">Ulga internetowa — poniesiony wydatek</string>
    <string name="pit_ikze">Wpłaty na IKZE</string>
    <string name="pit_donations">Darowizny</string>
    <string name="pit_joint_spouse">Rozliczenie wspólnie z małżonkiem</string>
    <string name="pit_data_required_error">Uzupełnij najpierw imię, nazwisko i urząd skarbowy</string>

    <string name="pit36_hint">Wybierz pełny rok kalendarzowy, sprawdź swoje dane osobowe, a następnie wygeneruj pomocniczy plik PDF z liczbami i wskazówkami do wypełnienia oficjalnego PIT-36 na podatki.gov.pl (Twój e-PIT) lub na papierze.</string>
    <string name="pit_row_przychod">Przychód</string>
    <string name="pit_row_koszty">Koszty</string>
    <string name="pit_row_dochod">Dochód</string>
    <string name="pit_row_tax">Szacowany podatek</string>
    <string name="pit_data_status_missing">Dane osobowe nie zostały jeszcze uzupełnione — są wymagane przed wygenerowaniem raportu.</string>
    <string name="pit_data_status_ready">Dane osobowe gotowe: %1$s</string>
    <string name="pit_edit_data_button">Edytuj dane osobowe</string>
    <string name="pit36_generate_button">Wygeneruj pomocniczy PDF PIT-36</string>
    <string name="pit36_disclaimer">Ten raport ma charakter wyłącznie informacyjny i nie jest oficjalnym formularzem PIT-36, e-Deklaracją ani poradą podatkową. Zawsze zweryfikuj liczby przed złożeniem deklaracji.</string>
    <string name="pit36_calculating">Trwa obliczanie, chwila…</string>
    <string name="pit36_generated">Raport PDF wygenerowany</string>
</resources>
EOF_STRINGS_XML
echo "OK: app/src/main/res/values-pl/strings.xml"

mkdir -p "$(dirname "app/src/main/res/values-ru/strings.xml")"
cat > "app/src/main/res/values-ru/strings.xml" << 'EOF_STRINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Добавить доход</string>
    <string name="add_expense">Добавить расход</string>
    <string name="add_entry">Добавить +</string>
    <string name="balance">Баланс</string>
    <string name="enter_amount">Сумма</string>
    <string name="enter_comment">Комментарий</string>
    <string name="attach_receipt">Прикрепить чек</string>
    <string name="save">Сохранить</string>
    <string name="settings">Настройки</string>
    <string name="tax_percent">Процент налога</string>
    <string name="other_income_label">Прочие доходы (%1$d)</string>
    <string name="tax_scale_title">Налог считается автоматически</string>
    <string name="tax_scale_description" formatted="false">0% до 30 000 zł/год · 12% с суммы от 30 000 до 120 000 zł · 32% с суммы свыше 120 000 zł. Ставка применяется только к части сверх каждого порога, а не ко всей сумме.</string>
    <string name="other_income_title">Прочие доходы</string>
    <string name="other_income_hint">Ваш общий налогооблагаемый доход за этот год из других источников (работа, другая деятельность и т.д.). Учитывается вместе с доходом из этого приложения при проверке годового необлагаемого лимита в 30 000 zł.</string>
    <string name="saved">Сохранено</string>
    <string name="auto_tax_button">Рассчитать автоматически</string>
    <string name="auto_tax_result">Предложенная ставка: %1$.1f%% (по шкале PIT: 12%% до 120 000 zł/год, 32%% свыше). Перед сохранением можно поправить вручную.</string>
    <string name="export_report">Экспорт отчёта</string>
    <string name="generate_report">Сгенерировать отчёт</string>
    <string name="select_period">Выберите период</string>
    <string name="month">Месяц</string>
    <string name="year">Год</string>
    <string name="custom_range">Произвольный период</string>
    <string name="from">От</string>
    <string name="to">До</string>
    <string name="no_entries">Нет записей</string>

    <string name="statistics">Статистика</string>
    <string name="stat_income">Доход</string>
    <string name="stat_expense">Расход</string>
    <string name="stat_profit">Прибыль (до налога)</string>
    <string name="stat_tax_format">Налог (%1$.1f%%)</string>

    <string name="report_col_date">Дата</string>
    <string name="report_col_income">Доход</string>
    <string name="report_col_expense">Расход</string>
    <string name="report_col_tax_percent">Налог %%</string>
    <string name="report_col_tax_amount">Сумма налога</string>
    <string name="report_col_comment">Комментарий</string>
    <string name="report_sheet_name">Отчёт</string>
    <string name="report_title_month">Отчёт — Месяц</string>
    <string name="report_title_year">Отчёт — Год</string>
    <string name="report_title_custom">Отчёт — Произвольный период</string>
    <string name="custom_range_invalid">Дата окончания должна быть позже даты начала</string>
    <string name="report_total_income">Итого доход</string>
    <string name="report_total_expense">Итого расход</string>
    <string name="report_total_profit">Итого прибыль</string>
    <string name="report_total_tax">Итого налог</string>
    <string name="report_total_net_profit">Чистая прибыль (после налога)</string>
    <string name="report_generating">Формирую отчёт…</string>
    <string name="report_ready">Отчёт готов</string>
    <string name="report_share_title">Поделиться отчётом</string>
    <string name="report_error">Ошибка формирования отчёта: %1$s</string>
    <string name="about_app">О приложении</string>
    <string name="about_description">FinArs — удобное приложение для ведения финансов нерегистрируемой деятельности. Легко учитывайте доходы и расходы, контролируйте текущий баланс, автоматически рассчитывайте налоги и формируйте отчёты. Приложение помогает соблюдать лимиты, отслеживать финансовые показатели и всегда иметь под рукой полную историю операций. Простой интерфейс и быстрый ввод данных делают ежедневный учёт максимально удобным.\n\nОсновные возможности:\n💰 Учёт доходов и расходов.\n📊 Автоматический расчёт прибыли.\n🧾 Расчёт налогов.\n📈 Контроль лимитов нерегистрируемой деятельности.\n📄 Генерация отчётов.\n🔍 История всех операций.\n🌙 Современный тёмный интерфейс.\n🔒 Все данные хранятся локально на устройстве.\n\nСвязь: p.arsenii@interia.pl</string>
    <string name="about_email">p.arsenii@interia.pl</string>
    <string name="dialog_close">Закрыть</string>
    <string name="dialog_write">Написать</string>
    <string name="pro_status_locked">Pro не активирован. Разблокируйте, чтобы получить годовые и произвольные отчёты в Excel, резервное копирование и восстановление, а также убрать рекламу.</string>
    <string name="pro_status_active">Pro активирован. Спасибо за поддержку!</string>
    <string name="pro_unlock_button">Разблокировать Pro</string>
    <string name="pro_unlock_button_price">Разблокировать Pro — %1$s</string>
    <string name="pro_loading">Загрузка цены…</string>
    <string name="pro_feature_locked_title">Функция Pro</string>
    <string name="pro_feature_locked_message">Годовые и произвольные отчёты доступны только в Pro-версии. Разблокируйте Pro в настройках.</string>
    <string name="pro_feature_locked_go_settings">Перейти в настройки</string>
    <string name="backup_pro_locked_message">Резервное копирование и восстановление — Pro-функция. Разблокируйте Pro, чтобы сохранить данные в файл на случай потери.</string>
    <string name="pro_purchase_error">Не удалось открыть окно оплаты. Проверьте соединение и попробуйте снова.</string>
    <string name="pro_info_title">Pro-версия</string>
    <string name="pro_info_message">Pro открывает:\n\n• Годовой отчёт в Excel\n• Отчёт за произвольный период\n• Резервное копирование и восстановление\n• Без рекламы\n\nЭто разовая покупка — платите один раз, доступ остаётся навсегда.</string>
    <string name="pro_info_continue">Перейти к покупке</string>
    <string name="enter_code_button">Есть код?</string>
    <string name="enter_code_title">Введите код</string>
    <string name="enter_code_hint">Код</string>
    <string name="enter_code_apply">Применить</string>
    <string name="enter_code_wrong">Неверный код</string>
    <string name="enter_code_success">Pro активирован</string>
    <string name="transaction_history">История операций</string>
    <string name="stat_net_profit">Чистая прибыль (после налога)</string>
    <string name="type_income">Доход</string>
    <string name="type_expense">Расход</string>
    <string name="edit_income_title">Редактировать доход</string>
    <string name="edit_expense_title">Редактировать расход</string>
    <string name="delete_entry">Удалить</string>
    <string name="delete_confirm_title">Удалить запись?</string>
    <string name="delete_confirm_message">Запись будет удалена без возможности восстановления.</string>
    <string name="delete_confirm_yes">Удалить</string>
    <string name="entry_updated">Обновлено</string>
    <string name="entry_deleted">Удалено</string>
    <string name="clear_all_button">Очистить все данные</string>
    <string name="clear_all_confirm_title">Вы уверены?</string>
    <string name="clear_all_confirm_message">Все доходы и расходы будут безвозвратно удалены. Это действие нельзя отменить.</string>
    <string name="clear_all_confirm_yes">Удалить всё</string>
    <string name="clear_all_done">Все данные удалены</string>

    <string name="settings_menu_tax">Налог и лимиты</string>
    <string name="settings_menu_language">Язык</string>
    <string name="settings_menu_backup">Резервная копия (Pro)</string>
    <string name="settings_menu_pro">Pro версия</string>

    <string name="backup_hint">Сохраните резервную копию доходов/расходов — суммы, даты, комментарии и прикреплённые фото чеков — в виде файла. В окне сохранения можно выбрать память телефона или Google Диск (если установлено приложение Диска). Храните этот файл в надёжном месте — только по нему можно восстановить данные при потере телефона или переустановке приложения.</string>
    <string name="backup_in_progress">Выполняется…</string>
    <string name="backup_create">Создать резервную копию</string>
    <string name="backup_restore">Восстановить из копии</string>
    <string name="backup_success">Копия сохранена (%1$d записей)</string>
    <string name="backup_error">Ошибка: %1$s</string>
    <string name="backup_restore_confirm_title">Восстановить из копии?</string>
    <string name="backup_restore_confirm_message">Записи из файла копии будут добавлены к тем, что уже есть на этом устройстве (существующие записи не удаляются и не перезаписываются). Если нужно "чистое" восстановление — сначала используйте "Очистить все данные", затем восстановление.</string>
    <string name="backup_invalid_file">Это не похоже на файл резервной копии FinArs</string>
    <string name="backup_restored">Восстановлено записей: %1$d</string>
    <string name="backup_never">Последняя копия: никогда</string>
    <string name="backup_last_time">Последняя копия: %1$s</string>

    <string name="settings_menu_security">Безопасность (PIN / отпечаток)</string>
    <string name="settings_menu_pit36">Сформировать PIT-36 (Pro)</string>
    <string name="pit36_pro_locked_message">Генерация PIT-36 — функция Pro. Разблокируйте Pro в настройках, чтобы ей пользоваться.</string>

    <string name="lock_title">FinArs заблокирован</string>
    <string name="lock_subtitle">Введите PIN, чтобы продолжить</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Неверный PIN, попробуйте ещё раз</string>
    <string name="lock_unlock_button">Разблокировать</string>
    <string name="lock_biometric_button">Войти по отпечатку / лицу</string>
    <string name="lock_biometric_prompt_title">Разблокировка FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Подтвердите отпечатком пальца или лицом</string>
    <string name="lock_use_pin">Ввести PIN</string>
    <string name="lock_biometric_unavailable">На этом устройстве не настроен отпечаток/лицо. Сначала добавьте его в настройках телефона.</string>

    <string name="security_hint">Защитите приложение PIN-кодом. Когда функция включена, FinArs будет спрашивать PIN каждый раз, когда вы возвращаетесь в приложение после его сворачивания. Также можно включить вход по отпечатку/лицу — это быстрый способ ввести тот же PIN.</string>
    <string name="security_pin_switch">Запрашивать PIN при открытии приложения</string>
    <string name="security_change_pin">Изменить PIN</string>
    <string name="security_biometric_switch">Вход по отпечатку / лицу</string>
    <string name="security_set_pin_title">Установите PIN</string>
    <string name="security_set_pin_message">Выберите PIN из 4–6 цифр</string>
    <string name="security_continue">Продолжить</string>
    <string name="security_pin_length_error">PIN должен состоять из 4–6 цифр</string>
    <string name="security_confirm_pin_title">Подтвердите PIN</string>
    <string name="security_pin_saved">PIN сохранён</string>
    <string name="security_pin_mismatch">PIN-коды не совпадают, попробуйте ещё раз</string>
    <string name="security_disable_pin_title">Введите текущий PIN</string>
    <string name="security_enter_current_pin">Введите текущий PIN, чтобы продолжить</string>
    <string name="security_pin_disabled">Защита PIN-ом отключена</string>

    <string name="pit_data_title">Личные данные для PIT-36</string>
    <string name="pit_data_hint">Используются только для заполнения вспомогательного отчёта PIT-36. Всё остаётся на вашем устройстве.</string>
    <string name="pit_first_name">Имя</string>
    <string name="pit_last_name">Фамилия</string>
    <string name="pit_pesel">PESEL (необязательно)</string>
    <string name="pit_street">Улица и номер дома/квартиры</string>
    <string name="pit_postal_code">Почтовый индекс</string>
    <string name="pit_city">Город</string>
    <string name="pit_tax_office">Налоговая инспекция (urząd skarbowy)</string>
    <string name="pit_reliefs_title">Льготы и вычеты (необязательно)</string>
    <string name="pit_children_count">Количество детей (ulga na dzieci)</string>
    <string name="pit_internet_relief">Льгота на интернет — сумма расходов</string>
    <string name="pit_ikze">Взносы на IKZE</string>
    <string name="pit_donations">Пожертвования (darowizny)</string>
    <string name="pit_joint_spouse">Совместная подача с супругом</string>
    <string name="pit_data_required_error">Сначала укажите имя, фамилию и налоговую инспекцию</string>

    <string name="pit36_hint">Выберите полный календарный год, проверьте личные данные, затем сформируйте вспомогательный PDF с цифрами и подсказками для заполнения официального PIT-36 на podatki.gov.pl (Twój e-PIT) или на бумаге.</string>
    <string name="pit_row_przychod">Przychód (доход)</string>
    <string name="pit_row_koszty">Koszty (расходы)</string>
    <string name="pit_row_dochod">Dochód (прибыль)</string>
    <string name="pit_row_tax">Расчётный налог</string>
    <string name="pit_data_status_missing">Личные данные ещё не заполнены — это нужно сделать перед формированием отчёта.</string>
    <string name="pit_data_status_ready">Личные данные готовы: %1$s</string>
    <string name="pit_edit_data_button">Изменить личные данные</string>
    <string name="pit36_generate_button">Сформировать вспомогательный PDF PIT-36</string>
    <string name="pit36_disclaimer">Этот отчёт носит исключительно информационный характер и не является официальным бланком PIT-36, e-Deklaracją или налоговой консультацией. Всегда перепроверяйте цифры перед подачей декларации.</string>
    <string name="pit36_calculating">Идёт расчёт, подождите…</string>
    <string name="pit36_generated">PDF-отчёт сформирован</string>
</resources>
EOF_STRINGS_XML
echo "OK: app/src/main/res/values-ru/strings.xml"

mkdir -p "$(dirname "app/src/main/AndroidManifest.xml")"
cat > "app/src/main/AndroidManifest.xml" << 'EOF_ANDROIDMANIFEST_XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />

    <application
        android:name=".FaApp"
        android:allowBackup="true"
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:theme="@style/Theme.FA">

        <!-- ЗАМЕНИТЬ на реальный AdMob App ID из консоли AdMob (Apps -> Ваше приложение -> App settings) -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-9218963926031039~6835956339" />

        <activity android:name=".SettingsActivity" android:exported="false" />
        <activity android:name=".SettingsProActivity" android:exported="false" />
        <activity android:name=".SettingsBackupActivity" android:exported="false" />
        <activity android:name=".SettingsLanguageActivity" android:exported="false" />
        <activity android:name=".SettingsTaxActivity" android:exported="false" />
        <activity android:name=".SettingsSecurityActivity" android:exported="false" />
        <activity android:name=".LockActivity" android:exported="false"
            android:launchMode="singleTask" android:excludeFromRecents="true" />
        <activity android:name=".PitDataActivity" android:exported="false" />
        <activity android:name=".Pit36Activity" android:exported="false" />
        <activity android:name=".AddEntryActivity" android:exported="false" />
        <activity android:name=".ReportActivity" android:exported="false" />
        <activity android:name=".HistoryActivity" android:exported="false" />
        <activity android:name=".MineActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
    </application>
</manifest>
EOF_ANDROIDMANIFEST_XML
echo "OK: app/src/main/AndroidManifest.xml"

mkdir -p "$(dirname "app/build.gradle")"
cat > "app/build.gradle" << 'EOF_BUILD_GRADLE'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
    id 'com.google.devtools.ksp'
}

android {
    signingConfigs {
        debug {
            storeFile file("debug.keystore")
            storePassword "fa_ksiegowy_debug"
            keyAlias "fa_ksiegowy_debug"
            keyPassword "fa_ksiegowy_debug"
        }
    }

    namespace "com.example.fa_ksiegowy"
    compileSdk 34

    defaultConfig {
        applicationId "com.example.fa_ksiegowy"
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "1.0"
        multiDexEnabled true
    }

    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = '17' }
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib:1.9.0"
    implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3"
    implementation "androidx.core:core-ktx:1.10.1"
    implementation "androidx.appcompat:appcompat:1.6.1"
    implementation "androidx.activity:activity-ktx:1.7.2"
    implementation "com.google.android.material:material:1.9.0"
    implementation "androidx.constraintlayout:constraintlayout:2.1.4"
    implementation "androidx.recyclerview:recyclerview:1.2.1"
    implementation "androidx.room:room-runtime:2.5.0"
    ksp "androidx.room:room-compiler:2.5.0"
    implementation "androidx.room:room-ktx:2.5.0"
    implementation "org.apache.poi:poi-ooxml:5.2.3"
    implementation "androidx.multidex:multidex:2.0.1"
    implementation "com.android.billingclient:billing-ktx:7.1.1"
    implementation "com.google.android.gms:play-services-ads:23.6.0"
    implementation "com.google.android.ump:user-messaging-platform:3.1.0"
    implementation "androidx.biometric:biometric:1.1.0"
}
EOF_BUILD_GRADLE
echo "OK: app/build.gradle"

echo "--- 4/4: готово ---"
echo "Изменения применены. Дальше как обычно:"
echo "  git add -A && git commit -m \"Add PIN/biometric lock and PIT-36 Pro generator\" && git push"
echo "После пуша сборка APK пойдёт через твой workflow на GitHub (Actions)."

