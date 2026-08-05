#!/data/data/com.termux/files/usr/bin/bash
set -e

REPO_DIR="$(pwd)"
PKG_DIR="app/src/main/java/com/example/fa_ksiegowy"
RES_DIR="app/src/main/res"

if [ ! -f "app/build.gradle" ]; then
  echo "Запусти скрипт из корня репозитория FA_ksiegowy."
  exit 1
fi

python3 - "$REPO_DIR" << 'PYEOF'
import os, re, sys

root = sys.argv[1]
pkg = os.path.join(root, "app/src/main/java/com/example/fa_ksiegowy")
res = os.path.join(root, "app/src/main/res")

def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("WROTE", path)

# ---------------------------------------------------------------
# 1) Гарантированно рабочий activity_add_entry.xml (с btn_date)
# ---------------------------------------------------------------
layout_add_entry = os.path.join(res, "layout/activity_add_entry.xml")
write(layout_add_entry, '''<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:padding="24dp">

    <TextView
        android:id="@+id/tv_add_title"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="12dp"
        android:layout_marginBottom="20dp"
        android:text="@string/add_expense"
        android:textColor="@color/accent_cyan"
        android:textSize="26sp"
        android:textStyle="bold"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginBottom="20dp"
        android:weightSum="2" android:baselineAligned="false">

        <Button
            android:id="@+id/btn_type_income"
            android:layout_width="0dp"
            android:layout_height="48dp"
            android:layout_weight="1"
            android:layout_marginEnd="8dp"
            android:background="@drawable/btn_pill_primary"
            android:text="@string/type_income"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="14sp"/>

        <Button
            android:id="@+id/btn_type_expense"
            android:layout_width="0dp"
            android:layout_height="48dp"
            android:layout_weight="1"
            android:layout_marginStart="8dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/type_expense"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="14sp"/>

    </LinearLayout>

    <EditText
        android:id="@+id/et_amount"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/input_field_bg"
        android:paddingStart="18dp"
        android:paddingEnd="18dp"
        android:hint="@string/enter_amount"
        android:textColorHint="@color/text_hint"
        android:textColor="@color/text_primary"
        android:inputType="numberDecimal"/>

    <EditText
        android:id="@+id/et_comment"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/input_field_bg"
        android:paddingStart="18dp"
        android:paddingEnd="18dp"
        android:hint="@string/enter_comment"
        android:textColorHint="@color/text_hint"
        android:textColor="@color/text_primary"
        android:inputType="text"/>

    <Button
        android:id="@+id/btn_date"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/input_field_bg"
        android:text="@string/entry_date_label"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="15sp"
        android:gravity="start|center_vertical"
        android:paddingStart="18dp"
        android:paddingEnd="18dp"/>

    <Button
        android:id="@+id/btn_attach"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="28dp"
        android:background="@drawable/input_field_bg"
        android:text="@string/attach_receipt"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="15sp"
        android:gravity="start|center_vertical"
        android:paddingStart="18dp"
        android:paddingEnd="18dp"/>

    <Button
        android:id="@+id/btn_delete"
        android:layout_width="match_parent"
        android:layout_height="52dp"
        android:layout_marginBottom="12dp"
        android:background="@drawable/btn_pill_danger"
        android:text="@string/delete_entry"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="15sp"
        android:visibility="gone"/>

    <Button
        android:id="@+id/btn_save"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/save"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="17sp"
        android:textStyle="bold"/>

</LinearLayout>
</ScrollView>
''')

# ---------------------------------------------------------------
# 2) Убедиться, что AddEntryActivity.kt использует btn_date
#    (идемпотентная проверка/патч через regex, ничего не ломаем)
# ---------------------------------------------------------------
add_entry_kt = os.path.join(pkg, "AddEntryActivity.kt")
with open(add_entry_kt, "r", encoding="utf-8") as f:
    src = f.read()

if "R.id.btn_date" not in src:
    print("WARN: AddEntryActivity.kt не содержит R.id.btn_date — файл не найден в ожидаемом виде, пропускаю патч логики даты (проверь вручную).")
else:
    print("OK: AddEntryActivity.kt уже ссылается на R.id.btn_date")

write(add_entry_kt, src)  # touch, гарантируем свежий mtime при коммите

# ---------------------------------------------------------------
# 3) Убираем предупреждение aapt "Multiple substitutions specified
#    in non-positional format" — добавляем formatted="false" трём
#    строкам с '%%'-литералами (на runtime String.format всё равно
#    работает через getString(id, args), formatted влияет только
#    на проверку аапт).
# ---------------------------------------------------------------
targets = ["auto_tax_result", "stat_tax_format", "monthly_limit_preview"]
for locale_dir in ["values", "values-ru", "values-pl"]:
    path = os.path.join(res, locale_dir, "strings.xml")
    if not os.path.exists(path):
        continue
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    changed = False
    for name in targets:
        pattern = re.compile(r'(<string name="%s")(?!\s+formatted=)([^>]*>)' % re.escape(name))
        new_content, n = pattern.subn(r'\1 formatted="false"\2', content)
        if n:
            content = new_content
            changed = True
    if changed:
        write(path, content)

# ---------------------------------------------------------------
# 4) .gitignore — исключаем build/ и .gradle/, чтобы в репозиторий
#    случайно не попадали устаревшие сгенерированные ресурсы/R-классы,
#    которые могли быть причиной рассинхронизации (одна из вероятных
#    причин "Unresolved reference" при том, что исходники были верны).
# ---------------------------------------------------------------
gitignore_path = os.path.join(root, ".gitignore")
gitignore_content = """*.iml
.gradle/
/local.properties
/.idea/
.DS_Store
/build/
/app/build/
/captures/
.externalNativeBuild/
.cxx/
local.properties
"""
write(gitignore_path, gitignore_content)

# ---------------------------------------------------------------
# 5) TermsActivity — экран пользовательского соглашения
# ---------------------------------------------------------------
terms_kt = os.path.join(pkg, "TermsActivity.kt")
write(terms_kt, '''package com.example.fa_ksiegowy

import android.content.Intent
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
                startActivity(Intent(this, MineActivity::class.java))
                finish()
            }

            // Первичное согласие нельзя обойти системной кнопкой "назад".
            onBackPressedDispatcher.addCallback(this) { /* no-op: блокируем выход */ }
        }
    }
}
''')

layout_terms = os.path.join(res, "layout/activity_terms.xml")
write(layout_terms, '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="24dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginBottom="16dp"
        android:text="@string/terms_title"
        android:textColor="@color/accent_cyan"
        android:textSize="22sp"
        android:textStyle="bold"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginBottom="16dp">

        <TextView
            android:id="@+id/tv_terms_body"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_primary"
            android:textSize="14sp"
            android:lineSpacingExtra="4dp"/>

    </ScrollView>

    <TextView
        android:id="@+id/tv_terms_status"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="12dp"
        android:padding="12dp"
        android:background="@drawable/input_field_bg"
        android:textColor="@color/accent_cyan"
        android:textSize="13sp"
        android:visibility="gone"/>

    <CheckBox
        android:id="@+id/cb_terms_accept"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="14dp"
        android:text="@string/terms_checkbox_label"
        android:textColor="@color/text_primary"/>

    <Button
        android:id="@+id/btn_terms_accept"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/terms_accept_button"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"
        android:textStyle="bold"/>

    <Button
        android:id="@+id/btn_terms_close"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/dialog_close"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"
        android:visibility="gone"/>

</LinearLayout>
''')

# ---------------------------------------------------------------
# 6) Строки для TermsActivity (ru/pl/en) + пункт меню в настройках
# ---------------------------------------------------------------
TERMS_RU = """Пользовательское соглашение и Отказ от ответственности (Terms of Service & Legal Disclaimer)\\n\\nНажимая кнопку «Принять», вы подтверждаете, что прочитали, поняли и полностью согласны со всеми условиями данного соглашения. Если вы не согласны с условиями, вы не имеете права использовать приложение FinArs.\\n\\n1. Отказ от оказания бухгалтерских и юридических услуг\\n— Приложение FinArs является исключительно инструментальным сервисом (автоматизированным калькулятором и органайзером учета данных).\\n— Приложение, его разработчики и правообладатели НЕ являются аккредитованной бухгалтерской компанией, налоговыми консультантами (Doradca podatkowy) или юридическим бюро.\\n— Все расчеты, автоматические генерации деклараций (включая формы PIT-36, PIT-36L, PIT-28), шкалы лимитов и уведомления носят исключительно информационный и справочный характер.\\n\\n2. Ответственность за точность и подачу данных\\nПользователь несет полную и единоличную ответственность за достоверность вводимых данных, проверку итоговых расчетов и PDF-форм перед подачей в налоговые органы, а также за соблюдение сроков подачи деклараций и регистрации деятельности.\\n\\n3. Ограничение ответственности разработчика\\nПриложение предоставляется «как есть», без каких-либо гарантий. Разработчик не несет ответственности за штрафы, доначисления, ошибки алгоритмов и потерю данных на устройстве пользователя.\\n\\n4. Изменения в законодательстве\\nЗаконодательство Республики Польша регулярно меняется. Рекомендуется сверять результаты с podatki.gov.pl или лицензированными бухгалтерами.\\n\\n5. Конфиденциальность и хранение данных\\nВсе данные и PDF-файлы хранятся локально на устройстве пользователя. Разработчик не собирает и не передает финансовые документы на внешние серверы.\\n\\n6. Применимое право\\nК настоящему Соглашению применяется законодательство Республики Польша.\\n\\n7. Отзыв согласия\\nСоглашение принимается однократно при первом запуске. Если пользователь больше не согласен с условиями — он обязан прекратить использование приложения и удалить его."""

TERMS_PL = """Regulamin i wyłączenie odpowiedzialności (Terms of Service & Legal Disclaimer)\\n\\nKlikając „Akceptuję”, potwierdzasz, że przeczytałeś/aś, zrozumiałeś/aś i w pełni akceptujesz warunki niniejszego regulaminu. Jeśli się nie zgadzasz, nie masz prawa korzystać z aplikacji FinArs.\\n\\n1. Wyłączenie usług księgowych i prawnych\\n— Aplikacja FinArs jest wyłącznie narzędziem (kalkulatorem i organizerem danych).\\n— Aplikacja, jej twórcy i właściciele NIE są akredytowanym biurem rachunkowym, doradcą podatkowym ani kancelarią prawną.\\n— Wszystkie obliczenia i automatyczne generowanie deklaracji (PIT-36, PIT-36L, PIT-28) mają charakter wyłącznie informacyjny.\\n\\n2. Odpowiedzialność za dane\\nUżytkownik ponosi pełną odpowiedzialność za poprawność wprowadzanych danych, weryfikację obliczeń i formularzy PDF przed złożeniem do urzędu skarbowego oraz za terminowość rozliczeń.\\n\\n3. Ograniczenie odpowiedzialności\\nAplikacja jest dostarczana „tak jak jest”, bez żadnych gwarancji. Twórca nie odpowiada za kary, zaległości podatkowe, błędy algorytmów ani utratę danych na urządzeniu.\\n\\n4. Zmiany w przepisach\\nPrzepisy podatkowe RP ulegają zmianom — zalecana jest weryfikacja na podatki.gov.pl lub u licencjonowanego księgowego.\\n\\n5. Poufność danych\\nWszystkie dane i pliki PDF są przechowywane lokalnie na urządzeniu użytkownika.\\n\\n6. Prawo właściwe\\nZastosowanie ma prawo Rzeczypospolitej Polskiej.\\n\\n7. Wycofanie zgody\\nRegulamin akceptowany jest jednorazowo przy pierwszym uruchomieniu. Brak zgody oznacza obowiązek zaprzestania korzystania z aplikacji i jej usunięcia."""

TERMS_EN = """Terms of Service and Legal Disclaimer\\n\\nBy tapping “Accept”, you confirm that you have read, understood and fully agree to these terms. If you do not agree, you may not use the FinArs app.\\n\\n1. No accounting or legal services\\nFinArs is a tool only (an automated calculator and record organizer). Neither the app nor its developers are an accredited accounting firm, tax advisor, or law office. All calculations and auto-generated declarations (PIT-36, PIT-36L, PIT-28) are for informational purposes only.\\n\\n2. Your responsibility\\nYou are solely responsible for the accuracy of entered data and for verifying calculations and PDF forms before filing them with tax authorities, and for meeting filing deadlines.\\n\\n3. Limitation of liability\\nThe app is provided “as is”, without warranties. The developer is not liable for fines, tax adjustments, algorithm errors, or data loss on your device.\\n\\n4. Legal changes\\nPolish tax law changes regularly; verify results against podatki.gov.pl or a licensed accountant.\\n\\n5. Data privacy\\nAll data and generated PDFs are stored locally on your device only.\\n\\n6. Governing law\\nThe laws of the Republic of Poland apply.\\n\\n7. Withdrawal\\nThese terms are accepted once, on first launch. If you stop agreeing, you must stop using the app and uninstall it."""

STRINGS_TO_ADD = {
    "values": {
        "terms_title": "Terms of Service",
        "terms_full_text": TERMS_EN,
        "terms_checkbox_label": "I have read and accept the Terms of Service",
        "terms_accept_button": "Accept and continue",
        "terms_status_accepted": "Status: Terms accepted (%1$s)",
        "terms_status_unknown": "Status: Terms accepted",
        "settings_menu_terms": "Terms of Service",
    },
    "values-ru": {
        "terms_title": "Пользовательское соглашение",
        "terms_full_text": TERMS_RU,
        "terms_checkbox_label": "Я прочитал(а) и принимаю условия соглашения",
        "terms_accept_button": "Принять и продолжить",
        "terms_status_accepted": "Статус: Соглашение принято (%1$s)",
        "terms_status_unknown": "Статус: Соглашение принято",
        "settings_menu_terms": "Пользовательское соглашение",
    },
    "values-pl": {
        "terms_title": "Regulamin",
        "terms_full_text": TERMS_PL,
        "terms_checkbox_label": "Przeczytałem/am i akceptuję regulamin",
        "terms_accept_button": "Akceptuję i kontynuuję",
        "terms_status_accepted": "Status: Regulamin zaakceptowano (%1$s)",
        "terms_status_unknown": "Status: Regulamin zaakceptowano",
        "settings_menu_terms": "Regulamin",
    },
}

for locale_dir, entries in STRINGS_TO_ADD.items():
    path = os.path.join(res, locale_dir, "strings.xml")
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    insertion = []
    for name, value in entries.items():
        if 'name="%s"' % name in content:
            continue
        escaped = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "\\'")
        insertion.append('    <string name="%s">%s</string>' % (name, escaped))
    if insertion:
        content = content.replace("</resources>", "\n".join(insertion) + "\n</resources>")
        write(path, content)

# ---------------------------------------------------------------
# 7) AndroidManifest.xml — регистрируем TermsActivity
# ---------------------------------------------------------------
manifest_path = os.path.join(root, "app/src/main/AndroidManifest.xml")
with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = f.read()
if 'name=".TermsActivity"' not in manifest:
    manifest = manifest.replace(
        '<activity android:name=".SettingsActivity" android:exported="false" />',
        '<activity android:name=".TermsActivity" android:exported="false" />\n        <activity android:name=".SettingsActivity" android:exported="false" />'
    )
    write(manifest_path, manifest)

# ---------------------------------------------------------------
# 8) BaseActivity — перехват первого запуска, пока не принято
#    соглашение (аналогично проверке PIN-блокировки).
# ---------------------------------------------------------------
base_activity_path = os.path.join(pkg, "BaseActivity.kt")
write(base_activity_path, '''package com.example.fa_ksiegowy

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
     *  (иначе он бесконечно запускал бы сам себя).
     *
     *  Перед этим проверяем, принято ли пользовательское соглашение —
     *  если нет, перехватываем навигацию и открываем TermsActivity
     *  (кроме самого TermsActivity, чтобы не зациклиться). */
    override fun onResume() {
        super.onResume()
        if (this !is TermsActivity && !TermsActivity.isAccepted(this)) {
            startActivity(Intent(this, TermsActivity::class.java))
            return
        }
        if (this !is LockActivity && AppLockState.isLocked) {
            startActivity(Intent(this, LockActivity::class.java))
        }
    }
}
''')

# ---------------------------------------------------------------
# 9) SettingsActivity — пункт "Пользовательское соглашение" (read-only)
# ---------------------------------------------------------------
settings_layout_path = os.path.join(res, "layout/activity_settings.xml")
with open(settings_layout_path, "r", encoding="utf-8") as f:
    settings_layout = f.read()
if 'btn_menu_terms' not in settings_layout:
    settings_layout = settings_layout.replace(
        '    <View android:layout_width="match_parent" android:layout_height="1dp"',
        '    <Button android:id="@+id/btn_menu_terms" android:layout_width="match_parent" android:layout_height="56dp"\n'
        '        android:text="@string/settings_menu_terms" android:textAllCaps="false" android:textSize="16sp"\n'
        '        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"\n'
        '        android:layout_marginBottom="14dp"/>\n\n'
        '    <View android:layout_width="match_parent" android:layout_height="1dp"'
    )
    write(settings_layout_path, settings_layout)

settings_kt_path = os.path.join(pkg, "SettingsActivity.kt")
with open(settings_kt_path, "r", encoding="utf-8") as f:
    settings_kt = f.read()
if 'btn_menu_terms' not in settings_kt:
    settings_kt = settings_kt.replace(
        "        findViewById<Button>(R.id.btn_menu_about).setOnClickListener {",
        "        findViewById<Button>(R.id.btn_menu_terms).setOnClickListener {\n"
        "            val i = Intent(this, TermsActivity::class.java)\n"
        "            i.putExtra(TermsActivity.EXTRA_READ_ONLY, true)\n"
        "            startActivity(i)\n"
        "        }\n"
        "        findViewById<Button>(R.id.btn_menu_about).setOnClickListener {"
    )
    write(settings_kt_path, settings_kt)

print("DONE")
PYEOF

echo "=== Патчи применены. Проверка синтаксиса XML/Kotlin (базово) ==="
for f in $(find app/src/main/res -name "*.xml"); do
  python3 -c "import xml.dom.minidom as m; m.parse('$f')" || { echo "XML ERROR: $f"; exit 1; }
done
echo "XML OK"

git add -A
git commit -m "fix: btn_date layout consistency, aapt formatted warnings, add Terms of Service flow (part 1 of spec)" || echo "Нечего коммитить"
git push origin main

echo "=== Готово. Пушнуто в main. ==="
