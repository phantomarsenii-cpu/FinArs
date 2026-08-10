#!/data/data/com.termux/files/usr/bin/bash
# Update 50: kasa fiskalna dla zarejestrowanej JDG dostepna od razu
# (bez czekania na przekroczenie limitu 20 000 zl gotowki).
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   cp "/storage/emulated/0/Download/DENIED/FA_ksiegowy_fixed-1 1/update_project-50-kasa-fiskalna-registered.sh" .
#   bash update_project-50-kasa-fiskalna-registered.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update50_backup_${TS}"

echo "=== Update 50: kasa fiskalna dla zarejestrowanej JDG dostepna od razu ==="
echo "Co sie zmienia:"
echo "  1) Blok potwierdzenia 'posiadam kase fiskalna' w Ustawienia -> Podatki"
echo "     pojawia sie NATYCHMIAST, gdy wybrana jest zarejestrowana JDG"
echo "     (skala/liniowy/ryczalt) - bez czekania na przekroczenie limitu"
echo "     20 000 zl gotowki."
echo "  2) Dla niezarejestrowanej dzialalnosci zachowanie bez zmian:"
echo "     blok pojawia sie dopiero po przekroczeniu tego limitu."
echo "  3) Przelaczanie typu dzialalnosci w Ustawieniach od razu odswieza"
echo "     widocznosc tego bloku (bez wychodzenia z ekranu)."
echo "  4) Osobny tekst podpowiedzi dla przypadku 'zarejestrowana JDG'"
echo "     (nie wspomina juz o przekroczonym limicie, ktorego moglo nie byc)."
echo

if [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
  echo "BLAD: nie widze app/src/main/java/com/example/fa_ksiegowy - uruchom skrypt z korzenia repo."
  exit 1
fi

mkdir -p "$BACKUP_DIR/app/src/main/java/com/example/fa_ksiegowy"
mkdir -p "$BACKUP_DIR/app/src/main/res/layout"
mkdir -p "$BACKUP_DIR/app/src/main/res/values"
mkdir -p "$BACKUP_DIR/app/src/main/res/values-pl"
mkdir -p "$BACKUP_DIR/app/src/main/res/values-ru"

backup() {
  cp "$1" "$BACKUP_DIR/$1"
}

backup "app/src/main/java/com/example/fa_ksiegowy/SettingsTaxActivity.kt"
backup "app/src/main/res/layout/activity_settings_tax.xml"
backup "app/src/main/res/values/strings.xml"
backup "app/src/main/res/values-pl/strings.xml"
backup "app/src/main/res/values-ru/strings.xml"

echo "--- Backup zmienianych plikow zapisany w $BACKUP_DIR ---"

python3 << 'PYEOF'
import sys

def str_replace(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    if count != 1:
        print(f"BLAD ({count} wystapien zamiast 1): {label} w {path}")
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {label} -> {path}")

# ---------------------------------------------------------------------------
# 1) SettingsTaxActivity.kt
# ---------------------------------------------------------------------------
KT = "app/src/main/java/com/example/fa_ksiegowy/SettingsTaxActivity.kt"

str_replace(
    KT,
    """            ActivityTypeHelper.set(prefs, type)
            updateNierejestrowanaFieldsVisibility(type)
        }
    }""",
    """            ActivityTypeHelper.set(prefs, type)
            updateNierejestrowanaFieldsVisibility(type)
            // Rejestracja JDG (skala/liniowy/ryczałt) od razu odblokowuje możliwość
            // potwierdzenia posiadania kasy fiskalnej — nie trzeba czekać na
            // przekroczenie limitu 20 000 zł, patrz setupKasaCompliance().
            setupKasaCompliance()
        }
    }""",
    "setupKasaCompliance() po zmianie typu dzialalnosci",
)

str_replace(
    KT,
    """    /**
     * Блок подтверждения наличия kasy fiskalnej — аналогично [setupVatCompliance],
     * появляется после превышения лимита 20 000 zł gotówki dla osób fizycznych.
     */
    private fun setupKasaCompliance() {
        val layout = findViewById<View>(R.id.layout_kasa_compliance)
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
        CoroutineScope(Dispatchers.IO).launch {
            val cash = CashLimitHelper.computeCurrentYear(applicationContext)
            withContext(Dispatchers.Main) {
                layout.visibility = if (cash.exceeded) View.VISIBLE else View.GONE
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
        }
    }""",
    """    /**
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
    }""",
    "setupKasaCompliance() + bindKasaCheckbox()",
)

# ---------------------------------------------------------------------------
# 2) layout/activity_settings_tax.xml — dodajemy id do hinta, zeby moc go
#    podmieniac w kodzie
# ---------------------------------------------------------------------------
XML = "app/src/main/res/layout/activity_settings_tax.xml"

str_replace(
    XML,
    """        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/kasa_compliance_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="10dp"/>
        <CheckBox android:id="@+id/cb_kasa_fiskalna\"""",
    """        <TextView android:id="@+id/tv_kasa_compliance_hint" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/kasa_compliance_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="10dp"/>
        <CheckBox android:id="@+id/cb_kasa_fiskalna\"""",
    "id tv_kasa_compliance_hint",
)

# ---------------------------------------------------------------------------
# 3) strings.xml (en / pl / ru) — nowy string kasa_compliance_hint_registered
# ---------------------------------------------------------------------------
str_replace(
    "app/src/main/res/values/strings.xml",
    '    <string name="kasa_compliance_hint">You have exceeded the 20,000 zł annual limit of cash sales to private individuals. A fiscal cash register may now be required. Confirm below once you have one — invoicing stays blocked until you do.</string>',
    '    <string name="kasa_compliance_hint">You have exceeded the 20,000 zł annual limit of cash sales to private individuals. A fiscal cash register may now be required. Confirm below once you have one — invoicing stays blocked until you do.</string>\n'
    '    <string name="kasa_compliance_hint_registered">Your business is registered (JDG), so you may already have a fiscal cash register from the start. If you do, confirm it below — this unlocks the \\"issued for a receipt\\" option when filling out invoices.</string>',
    "kasa_compliance_hint_registered (values/strings.xml)",
)

str_replace(
    "app/src/main/res/values-pl/strings.xml",
    '    <string name="kasa_compliance_hint">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Może być wymagana kasa fiskalna. Potwierdź poniżej, gdy ją posiadasz — wystawianie faktur pozostaje zablokowane do tego czasu.</string>',
    '    <string name="kasa_compliance_hint">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Może być wymagana kasa fiskalna. Potwierdź poniżej, gdy ją posiadasz — wystawianie faktur pozostaje zablokowane do tego czasu.</string>\n'
    '    <string name="kasa_compliance_hint_registered">Twoja działalność jest zarejestrowana (JDG), więc mogłeś/aś posiadać kasę fiskalną już od początku. Jeśli tak, potwierdź to poniżej — odblokuje to opcję „wydana do paragonu\\" przy wystawianiu faktur.</string>',
    "kasa_compliance_hint_registered (values-pl/strings.xml)",
)

str_replace(
    "app/src/main/res/values-ru/strings.xml",
    '    <string name="kasa_compliance_hint">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Может понадобиться кассовый аппарат. Подтвердите ниже, когда он у вас появится — до этого выставление фактур остаётся заблокированным.</string>',
    '    <string name="kasa_compliance_hint">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Может понадобиться кассовый аппарат. Подтвердите ниже, когда он у вас появится — до этого выставление фактур остаётся заблокированным.</string>\n'
    '    <string name="kasa_compliance_hint_registered">Ваша деятельность зарегистрирована (JDG), поэтому кассовый аппарат у вас мог быть уже с самого начала. Если это так, подтвердите это ниже — это откроет опцию «выдана к чеку» при заполнении фактур.</string>',
    "kasa_compliance_hint_registered (values-ru/strings.xml)",
)

print()
print("=== Update 50 zastosowany pomyslnie ===")
PYEOF

echo
echo "Zaden plik binarny nie zostal zmieniony."
echo "Baza danych (Room) NIE zostala zmieniona - nie trzeba nic migrowac."
echo "Dalej jak zwykle:"
echo "  git add -A && git commit -m 'update 50: kasa fiskalna dla zarejestrowanej JDG od razu' && git push"
echo "Zbuduj APK przez GitHub Actions."
