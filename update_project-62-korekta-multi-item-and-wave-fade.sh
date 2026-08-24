#!/data/data/com.termux/files/usr/bin/bash
# Update 62: dwie niezwiazane ze soba poprawki.
#
# 1) Faktura korygujaca (korekta) do faktury z KILKOMA pozycjami: dotychczas mozna
#    bylo wybrac tylko JEDNA pozycje do korekty na raz - zeby skorygowac wiecej niz
#    jedna pozycje, trzeba bylo wystawiac osobna korekte na kazda z nich, co bylo
#    niepoprawne (jedna korekta powinna moc objac kilka pozycji naraz). Teraz
#    przycisk "Wybierz pozycje" otwiera wlasny dialog w stylu aplikacji (ciemna
#    karta + przyciski-pigulki, patrz AppDialog.showMultiCheckboxPicker) zamiast
#    standardowego systemowego Spinnera (ktory renderowal sie jako "czarne",
#    niepasujace do reszty interfejsu okienko) - mozna zaznaczyc dowolna liczbe
#    pozycji checkboxami, dla kazdej zaznaczonej pojawia sie osobne pole "Kwota po
#    korekcie", i dopiero wtedy wystawia sie JEDNA korekta obejmujaca wszystkie
#    zaznaczone pozycje naraz.
#
# 2) Dekoracyjne faliste linie w naglowku/stopce PDF (faktura + korekta) urywaly
#    sie nagle na pelnej kryciu tam, gdzie obrazek jest sztucznie przyciety
#    (wewnetrzna krawedz, nie prawdziwa krawedz strony) - teraz ta krawedz jest
#    rozmyta maska CSS (mask-image gradient) do przezroczystosci, dajac plynne,
#    "znikajace" pojawienie sie linii zamiast ostrego uciecia.
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-62-korekta-multi-item-and-wave-fade.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update62_backup_${TS}"

echo "=== Update 62: korekta wielu pozycji naraz + plynne pojawienie fal na PDF ==="
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
  echo "BLAD: nie widze settings.gradle lub app/src/main/java/com/example/fa_ksiegowy - uruchom skrypt z korzenia repo."
  exit 1
fi

if grep -q "correctedItems: Map<Int, Double>" "app/src/main/java/com/example/fa_ksiegowy/InvoiceHtmlPdfGenerator.kt" 2>/dev/null; then
  echo "!!! Wyglada na to, ze update_project-62 zostal juz zastosowany (InvoiceHtmlPdfGenerator.kt ma juz correctedItems)."
  exit 1
fi

mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/AppDialog.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceHtmlPdfGenerator.kt" \
    "app/src/main/res/layout/activity_add_invoice_correction.xml" \
    "app/src/main/assets/invoice_template.html" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/res/values-ru/strings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "Kopia zapasowa zapisana w: $BACKUP_DIR"
echo ""

echo "-> app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt (pelna wymiana)"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/AddInvoiceCorrectionActivity.kt' << 'FAEOF_ADDINVOICECORRECTIONACTIVITY_KT'
package com.example.fa_ksiegowy

import android.os.Bundle
import android.text.InputType
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Update: экран выставления Faktura korygująca (корректировочной фактуры) к уже
 * выставленному документу. Открывается из InvoiceHistoryActivity по кнопке "↺"
 * на строке фактуры (см. InvoiceAdapter/item_invoice.xml), обязательный extra —
 * EXTRA_INVOICE_ID.
 *
 * Update 62: если у оригинальной фактуры больше 1 позиции — теперь можно выбрать
 * НЕСКОЛЬКО позиций сразу (btn_pick_items открывает AppDialog.showMultiCheckboxPicker —
 * то же самое оформление диалогов, что и во всём приложении, вместо стандартного
 * системного Spinner-попапа). Для каждой выбранной позиции показывается отдельное
 * поле "Kwota po korekcie" (см. rebuildSelectedItemsRows) — остальные, невыбранные
 * позиции остаются без изменений. Итоговая скорректированная сумма считается как
 * originalInvoice.amount минус сумма старых значений выбранных позиций плюс сумма
 * новых значений. Раньше можно было скорректировать только ОДНУ позицию за раз —
 * для нескольких позиций пользователю приходилось выставлять отдельную корректу на
 * каждую, что было неверно (одна корректировка должна покрывать все изменения сразу).
 * Для фактур с 0-1 позицией поведение не изменилось (корректировка всей суммы одним
 * полем et_corrected_amount).
 *
 * Дельта (correctedAmount - originalAmount) может быть, по желанию пользователя
 * (галочка cb_apply_to_income, отмечена по умолчанию), сразу же записана как Entry
 * (isIncome=true, amount=delta) — это тот же самый механизм, которым обычные
 * приходы уже участвуют в расчёте Dochód/Podatek/лимитов (см. TaxHelper/LimitsHelper),
 * поэтому отдельно трогать их не нужно: отрицательная delta корректно уменьшит
 * Przychód, положительная — увеличит.
 */
class AddInvoiceCorrectionActivity : BaseActivity() {

    companion object {
        const val EXTRA_INVOICE_ID = "invoiceId"
    }

    private lateinit var originalInvoice: Invoice
    private var originalItems: List<InvoiceItem> = emptyList()

    // Update 62: индексы (в originalItems) выбранных для корректировки позиций,
    // в порядке выбора; для каждой — уже введённое/предзаполненное значение "Kwota
    // po korekcie", сохраняется при переоткрытии диалога выбора, чтобы не сбрасывать
    // то, что пользователь уже ввёл.
    private val selectedItemIndices = LinkedHashSet<Int>()
    private val itemPendingValues = LinkedHashMap<Int, Double>()
    private val itemAmountFields = LinkedHashMap<Int, EditText>()

    private val moneyFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_invoice_correction)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }

        val invoiceId = intent.getLongExtra(EXTRA_INVOICE_ID, -1L)
        if (invoiceId < 0) {
            finish()
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val invoice = db.invoiceDao().getById(invoiceId)
            val items = if (invoice != null) db.invoiceItemDao().getForInvoice(invoice.id) else emptyList()
            withContext(Dispatchers.Main) {
                if (invoice == null) {
                    finish()
                    return@withContext
                }
                originalInvoice = invoice
                originalItems = items
                bindOriginalInvoiceInfo()
                setupItemPicker()
            }
        }

        findViewById<Button>(R.id.btn_save_correction).setOnClickListener { saveCorrection() }
    }

    private fun bindOriginalInvoiceInfo() {
        findViewById<TextView>(R.id.tv_original_invoice_info).text =
            getString(R.string.correction_original_invoice_label, originalInvoice.invoiceNumber, originalInvoice.buyerName)
        val amountStr = String.format(Locale.getDefault(), "%.2f", originalInvoice.amount)
        findViewById<TextView>(R.id.tv_original_amount).text =
            "${getString(R.string.correction_original_amount_label)}: $amountStr zł · ${moneyFmt.format(Date(originalInvoice.issueDateMillis))}"
        findViewById<EditText>(R.id.et_corrected_amount).setText(
            String.format(Locale.US, "%.2f", originalInvoice.amount)
        )
    }

    /** Update 62: pokazuje wybór WIELU pozycji do korekty tylko gdy oryginalna faktura
     *  ma >1 pozycję — dla 0-1 pozycji zachowanie zostaje dokładnie takie jak wcześniej
     *  (pojedyncze pole et_corrected_amount dla całej faktury). */
    private fun setupItemPicker() {
        if (originalItems.size <= 1) return

        findViewById<LinearLayout>(R.id.ll_item_picker).visibility = android.view.View.VISIBLE
        // W trybie wielu pozycji kwota "całej faktury" nie ma zastosowania — liczy się
        // z sumy pól per-pozycja (patrz rebuildSelectedItemsRows/saveCorrection).
        findViewById<TextView>(R.id.tv_corrected_amount_label).visibility = android.view.View.GONE
        findViewById<EditText>(R.id.et_corrected_amount).visibility = android.view.View.GONE

        findViewById<Button>(R.id.btn_pick_items).setOnClickListener { openItemPickerDialog() }
        rebuildSelectedItemsRows()
    }

    /** Update 62: własny dialog w stylu aplikacji (AppDialog — ciemna karta, przyciski-
     *  pigułki), zamiast systemowego Spinnera, który otwierał standardowe, "czarne"
     *  okienko niepasujące do reszty interfejsu. Pozwala zaznaczyć checkboxami DOWOLNĄ
     *  liczbę pozycji naraz. */
    private fun openItemPickerDialog() {
        val options = originalItems.mapIndexed { index, item ->
            val value = item.quantity * item.unitPrice
            index to "${item.name} — ${String.format(Locale.getDefault(), "%.2f", value)} zł"
        }
        AppDialog.showMultiCheckboxPicker(
            context = this,
            title = getString(R.string.correction_pick_items_dialog_title),
            options = options,
            preselected = selectedItemIndices,
            confirmText = getString(R.string.correction_pick_items_confirm),
            cancelText = getString(R.string.confirm_cancel)
        ) { chosen ->
            // Zachowujemy już wpisane kwoty dla pozycji, które nadal są zaznaczone;
            // dla nowo zaznaczonych pozycji podpowiadamy oryginalną wartość.
            selectedItemIndices.clear()
            for (idx in originalItems.indices) {
                if (chosen.contains(idx)) selectedItemIndices.add(idx)
            }
            itemPendingValues.keys.retainAll(selectedItemIndices)
            rebuildSelectedItemsRows()
        }
    }

    /** Update 62: buduje dynamicznie po jednym polu "Kwota po korekcie" dla każdej
     *  zaznaczonej pozycji wewnątrz ll_selected_items_amounts. */
    private fun rebuildSelectedItemsRows() {
        val container = findViewById<LinearLayout>(R.id.ll_selected_items_amounts)
        container.removeAllViews()
        itemAmountFields.clear()

        val emptyHint = findViewById<TextView>(R.id.tv_no_items_selected)
        emptyHint.visibility = if (selectedItemIndices.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE

        val density = resources.displayMetrics.density
        for (idx in selectedItemIndices) {
            val item = originalItems.getOrNull(idx) ?: continue
            val oldValue = item.quantity * item.unitPrice

            val row = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                lp.topMargin = (14 * density).toInt()
                layoutParams = lp
            }

            val label = TextView(this).apply {
                text = "${item.name} · ${getString(R.string.correction_original_amount_label)}: " +
                    "${String.format(Locale.getDefault(), "%.2f", oldValue)} zł"
                textSize = 13f
                setTextColor(resources.getColor(R.color.text_secondary, theme))
            }
            row.addView(label)

            val amountField = EditText(this).apply {
                setText(String.format(Locale.US, "%.2f", itemPendingValues[idx] ?: oldValue))
                inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
                setTextColor(resources.getColor(R.color.text_primary, theme))
                setBackgroundResource(R.drawable.input_field_bg)
                val padH = (18 * density).toInt()
                setPadding(padH, 0, padH, 0)
                val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (52 * density).toInt())
                lp.topMargin = (6 * density).toInt()
                layoutParams = lp
            }
            row.addView(amountField)

            container.addView(row)
            itemAmountFields[idx] = amountField
        }
    }

    private fun saveCorrection() {
        val reason = findViewById<EditText>(R.id.et_reason).text.toString().trim()
        if (reason.isBlank()) {
            Toast.makeText(this, getString(R.string.correction_reason_required_error), Toast.LENGTH_SHORT).show()
            return
        }

        // Update 62: w trybie "wiele pozycji" (>1 pozycji na oryginalnej fakturze) każda
        // zaznaczona pozycja ma własną wpisaną kwotę — całkowita skorygowana kwota
        // faktury to originalInvoice.amount pomniejszone o sumę starych wartości
        // zaznaczonych pozycji i powiększone o sumę nowo wpisanych. Pozostałe pozycje
        // (niezaznaczone) zostają bez zmian.
        val correctedItems = LinkedHashMap<Int, Double>()
        val corrected: Double

        if (originalItems.size > 1) {
            if (selectedItemIndices.isEmpty()) {
                Toast.makeText(this, getString(R.string.correction_no_items_selected_error), Toast.LENGTH_SHORT).show()
                return
            }
            var sumOld = 0.0
            var sumNew = 0.0
            for (idx in selectedItemIndices) {
                val field = itemAmountFields[idx] ?: continue
                val text = field.text.toString().replace(",", ".").trim()
                val value = text.toDoubleOrNull()
                if (value == null) {
                    Toast.makeText(this, getString(R.string.enter_amount), Toast.LENGTH_SHORT).show()
                    return
                }
                itemPendingValues[idx] = value
                val oldValue = originalItems[idx].quantity * originalItems[idx].unitPrice
                sumOld += oldValue
                sumNew += value
                correctedItems[idx] = value
            }
            corrected = originalInvoice.amount - sumOld + sumNew
        } else {
            val correctedText = findViewById<EditText>(R.id.et_corrected_amount).text.toString().replace(",", ".").trim()
            val enteredValue = correctedText.toDoubleOrNull()
            if (enteredValue == null) {
                Toast.makeText(this, getString(R.string.enter_amount), Toast.LENGTH_SHORT).show()
                return
            }
            corrected = enteredValue
        }

        val delta = corrected - originalInvoice.amount
        if (delta == 0.0) {
            Toast.makeText(this, getString(R.string.correction_zero_delta_error), Toast.LENGTH_SHORT).show()
            return
        }
        val applyToIncome = findViewById<CheckBox>(R.id.cb_apply_to_income).isChecked
        val btn = findViewById<Button>(R.id.btn_save_correction)
        btn.isEnabled = false

        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val correctionNumber = (db.invoiceCorrectionDao().getMaxCorrectionNumber() ?: 0) + 1
            val issueDateMillis = System.currentTimeMillis()
            val fileName = FileNaming.invoiceCorrectionFileName(correctionNumber, issueDateMillis)
            val originalVatRate = VatRate.fromStorageKeyOrNull(originalInvoice.vatRate)

            val pdfBytes = withContext(Dispatchers.Main) {
                InvoiceHtmlPdfGenerator.generateCorrection(
                    context = this@AddInvoiceCorrectionActivity,
                    seller = InvoiceSellerDataStore.load(applicationContext),
                    correctionNumber = correctionNumber,
                    issueDateMillis = issueDateMillis,
                    originalInvoiceNumber = originalInvoice.invoiceNumber,
                    originalIssueDateMillis = originalInvoice.issueDateMillis,
                    buyerName = originalInvoice.buyerName,
                    buyerNip = originalInvoice.buyerNip,
                    buyerStreet = originalInvoice.buyerStreet,
                    buyerPostalCode = originalInvoice.buyerPostalCode,
                    buyerCity = originalInvoice.buyerCity,
                    originalAmount = originalInvoice.amount,
                    correctedAmount = corrected,
                    reason = reason,
                    items = originalItems,
                    vatRate = originalVatRate,
                    correctedItems = correctedItems
                )
            }
            val saved = InvoiceFileStorage.savePdf(applicationContext, fileName) { out ->
                out.write(pdfBytes)
            }

            db.invoiceCorrectionDao().insert(
                InvoiceCorrection(
                    originalInvoiceId = originalInvoice.id,
                    originalInvoiceNumber = originalInvoice.invoiceNumber,
                    correctionNumber = correctionNumber,
                    issueDateMillis = issueDateMillis,
                    reason = reason,
                    originalAmount = originalInvoice.amount,
                    correctedAmount = corrected,
                    deltaAmount = delta,
                    pdfFilePath = saved.uri.toString(),
                    pdfFileName = fileName,
                    appliedToIncome = applyToIncome
                )
            )

            if (applyToIncome) {
                db.entryDao().insert(
                    Entry(
                        amount = delta,
                        isIncome = true,
                        comment = getString(R.string.correction_pdf_title) + " ${correctionNumber} — " +
                            getString(R.string.correction_pdf_to_invoice) + " ${originalInvoice.invoiceNumber}",
                        dateMillis = issueDateMillis,
                        receiptPath = null,
                        ryczaltCategory = null
                    )
                )
            }

            withContext(Dispatchers.Main) {
                Toast.makeText(this@AddInvoiceCorrectionActivity, getString(R.string.correction_saved_toast), Toast.LENGTH_SHORT).show()
                InvoiceFileStorage.openPdfSafely(this@AddInvoiceCorrectionActivity, saved.uri.toString())
                finish()
            }
        }
    }
}
FAEOF_ADDINVOICECORRECTIONACTIVITY_KT

echo "-> app/src/main/java/com/example/fa_ksiegowy/AppDialog.kt (pelna wymiana)"
mkdir -p "$(dirname 'app/src/main/java/com/example/fa_ksiegowy/AppDialog.kt')"
cat > 'app/src/main/java/com/example/fa_ksiegowy/AppDialog.kt' << 'FAEOF_APPDIALOG_KT'
package com.example.fa_ksiegowy

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Единый стиль всплывающих диалогов приложения — тёмная карточка (card_bg) со
 * скруглёнными углами и кнопками-пилюлями (btn_pill_primary/btn_pill_outline),
 * вместо стандартного светлого системного AlertDialog, который визуально выбивался
 * из тёмного интерфейса приложения. Используется и для простых диалогов с полем
 * ввода (см. InventoryActivity — количество при сканировании), и для компактного
 * вертикального меню выбора одного варианта (см. showOptionPicker — категория
 * ryczałtu в AddEntryActivity/AddInvoiceActivity), и для выбора НЕСКОЛЬКИХ вариантов
 * чекбоксами (см. showMultiCheckboxPicker — позиции для Faktura korygująca в
 * AddInvoiceCorrectionActivity).
 */
object AppDialog {

    /** Небольшая карточка-диалог: заголовок + необязательное сообщение + произвольный
     *  контент (например EditText или список вариантов) + одна или две кнопки-пилюли
     *  снизу. Возвращает созданный Dialog — можно дополнительно повесить
     *  setOnShowListener (например, чтобы показать клавиатуру). */
    fun show(
        context: Context,
        title: String,
        message: String? = null,
        contentView: View? = null,
        positiveText: String,
        onPositive: () -> Unit,
        negativeText: String? = null,
        onNegative: (() -> Unit)? = null,
        cancelable: Boolean = true
    ): Dialog {
        val density = context.resources.displayMetrics.density
        val pad = (20 * density).toInt()

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.card_bg)
            setPadding(pad, pad, pad, pad)
        }

        val tvTitle = TextView(context).apply {
            text = title
            setTextColor(context.resources.getColor(R.color.accent_cyan, context.theme))
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
        }
        root.addView(tvTitle)

        if (!message.isNullOrBlank()) {
            val tvMsg = TextView(context).apply {
                text = message
                setTextColor(context.resources.getColor(R.color.text_secondary, context.theme))
                textSize = 13f
                setPadding(0, (8 * density).toInt(), 0, 0)
            }
            root.addView(tvMsg)
        }

        contentView?.let { cv ->
            (cv.parent as? ViewGroup)?.removeView(cv)
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.topMargin = (14 * density).toInt()
            root.addView(cv, lp)
        }

        val buttonsRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.topMargin = (20 * density).toInt()
            layoutParams = lp
        }

        val dialog = Dialog(context)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setCancelable(cancelable)
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))

        if (negativeText != null) {
            val btnNeg = Button(context).apply {
                text = negativeText
                isAllCaps = false
                setTextColor(context.resources.getColor(R.color.text_secondary, context.theme))
                setBackgroundResource(R.drawable.btn_pill_outline)
                setOnClickListener {
                    onNegative?.invoke()
                    dialog.dismiss()
                }
            }
            val lpNeg = LinearLayout.LayoutParams(0, (48 * density).toInt(), 1f)
            lpNeg.marginEnd = (8 * density).toInt()
            buttonsRow.addView(btnNeg, lpNeg)
        }

        val btnPos = Button(context).apply {
            text = positiveText
            isAllCaps = false
            setTextColor(context.resources.getColor(R.color.text_primary, context.theme))
            setBackgroundResource(R.drawable.btn_pill_primary)
            setOnClickListener {
                onPositive()
                dialog.dismiss()
            }
        }
        val lpPos = LinearLayout.LayoutParams(0, (48 * density).toInt(), 1f)
        if (negativeText != null) lpPos.marginStart = (8 * density).toInt()
        buttonsRow.addView(btnPos, lpPos)

        root.addView(buttonsRow)
        dialog.setContentView(root)
        dialog.window?.setLayout(
            (context.resources.displayMetrics.widthPixels * 0.86).toInt(),
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        dialog.window?.setGravity(Gravity.CENTER)
        dialog.show()
        return dialog
    }

    /** Компактное вертикальное меню выбора ОДНОГО варианта из списка — маленький
     *  всплывающий диалог в стиле приложения (не системное меню), каждый вариант —
     *  отдельная "таблетка". Закрывается сразу после выбора одного из вариантов. */
    fun showOptionPicker(
        context: Context,
        title: String,
        options: List<Pair<String, String>>,
        onSelected: (String) -> Unit
    ) {
        val density = context.resources.displayMetrics.density
        val container = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val dialogRef = arrayOfNulls<Dialog>(1)

        for ((index, pair) in options.withIndex()) {
            val (value, label) = pair
            val btn = Button(context).apply {
                text = label
                isAllCaps = false
                textSize = 14f
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                setPadding((18 * density).toInt(), 0, (18 * density).toInt(), 0)
                setTextColor(context.resources.getColor(R.color.text_primary, context.theme))
                setBackgroundResource(R.drawable.input_field_bg)
                setOnClickListener {
                    onSelected(value)
                    dialogRef[0]?.dismiss()
                }
            }
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (52 * density).toInt())
            if (index > 0) lp.topMargin = (10 * density).toInt()
            container.addView(btn, lp)
        }

        val dialog = show(
            context = context,
            title = title,
            contentView = container,
            positiveText = context.getString(R.string.dialog_close),
            onPositive = {},
            cancelable = true
        )
        dialogRef[0] = dialog
    }

    /** Update 62: вертикальный список чекбоксов для выбора НЕСКОЛЬКИХ вариантов сразу
     *  (используется для выбора позиций фактуры при Faktura korygująca) — в стиле
     *  приложения (card_bg + pill-кнопки), вместо системного диалога/Spinner-попапа,
     *  который рендерится стандартным (обычно тёмным) системным стилем, выбивающимся
     *  из дизайна приложения. options — список пар (id, подпись); id — произвольный
     *  идентификатор варианта (например индекс позиции в списке), возвращается в
     *  onConfirm как Set выбранных id. Диалог закрывается по кнопке confirmText —
     *  onConfirm вызывается только тогда (кнопка cancelText просто закрывает диалог
     *  без вызова колбэка). */
    fun showMultiCheckboxPicker(
        context: Context,
        title: String,
        options: List<Pair<Int, String>>,
        preselected: Set<Int>,
        confirmText: String,
        cancelText: String,
        onConfirm: (Set<Int>) -> Unit
    ) {
        val density = context.resources.displayMetrics.density
        val container = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val checkBoxes = mutableListOf<Pair<Int, CheckBox>>()

        for ((index, pair) in options.withIndex()) {
            val (id, label) = pair
            val cb = CheckBox(context).apply {
                text = label
                textSize = 14f
                setTextColor(context.resources.getColor(R.color.text_primary, context.theme))
                isChecked = preselected.contains(id)
            }
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            if (index > 0) lp.topMargin = (12 * density).toInt()
            container.addView(cb, lp)
            checkBoxes.add(id to cb)
        }

        show(
            context = context,
            title = title,
            contentView = container,
            positiveText = confirmText,
            onPositive = {
                val selected = checkBoxes.filter { it.second.isChecked }.map { it.first }.toSet()
                onConfirm(selected)
            },
            negativeText = cancelText,
            onNegative = {},
            cancelable = true
        )
    }
}
FAEOF_APPDIALOG_KT

echo "-> app/src/main/res/layout/activity_add_invoice_correction.xml (pelna wymiana)"
mkdir -p "$(dirname 'app/src/main/res/layout/activity_add_invoice_correction.xml')"
cat > 'app/src/main/res/layout/activity_add_invoice_correction.xml' << 'FAEOF_LAYOUT_XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:paddingStart="20dp" android:paddingEnd="20dp"
    android:paddingTop="28dp" android:paddingBottom="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="20dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/correction_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <LinearLayout
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg"
        android:padding="16dp" android:layout_marginBottom="18dp">
        <TextView android:id="@+id/tv_original_invoice_info" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_primary" android:textSize="14sp" android:layout_marginBottom="8dp"/>
        <TextView android:id="@+id/tv_original_amount" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_secondary" android:textSize="13sp"/>
    </LinearLayout>

    <!-- Update 62: wybór WIELU pozycji do korekty naraz — widoczny tylko gdy oryginalna
         faktura ma więcej niż 1 pozycję (dla faktur z jedną pozycją zachowanie jest jak
         dotychczas: kwota po korekcie odnosi się do całej faktury, pole et_corrected_amount
         poniżej). Przycisk btn_pick_items otwiera dialog w stylu aplikacji
         (AppDialog.showMultiCheckboxPicker) zamiast standardowego systemowego Spinnera. -->
    <LinearLayout android:id="@+id/ll_item_picker" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:visibility="gone" android:layout_marginBottom="14dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/correction_item_picker_hint" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
        <Button android:id="@+id/btn_pick_items" android:layout_width="match_parent" android:layout_height="52dp"
            android:text="@string/correction_pick_items_button" android:textAllCaps="false" android:textSize="14sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>
        <TextView android:id="@+id/tv_no_items_selected" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/correction_no_items_selected_hint" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:layout_marginTop="10dp"/>
        <LinearLayout android:id="@+id/ll_selected_items_amounts" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="vertical"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_corrected_amount_label" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/correction_corrected_amount_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
    <EditText android:id="@+id/et_corrected_amount" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
        android:textColor="@color/text_primary" android:inputType="numberDecimal"
        android:layout_marginBottom="14dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/correction_reason_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
    <EditText android:id="@+id/et_reason" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:minLines="2" android:gravity="top|start"
        android:background="@drawable/input_field_bg" android:padding="18dp"
        android:textColor="@color/text_primary" android:inputType="textMultiLine"
        android:layout_marginBottom="16dp"/>

    <CheckBox android:id="@+id/cb_apply_to_income" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/correction_apply_to_income_label" android:textColor="@color/text_primary"
        android:textSize="13sp" android:checked="true" android:layout_marginBottom="24dp"/>

    <Button android:id="@+id/btn_save_correction" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/correction_save_button" android:textAllCaps="false" android:textSize="16sp"
        android:textStyle="bold" android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>

</LinearLayout>
    </ScrollView>
</FrameLayout>
FAEOF_LAYOUT_XML

echo "-> punktowe patche (Python, idempotentne): InvoiceHtmlPdfGenerator.kt, invoice_template.html, strings.xml (en/pl/ru)"
python3 << 'PYEOF'
import sys

def str_replace_any(path, candidates, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if new in content:
        print(f"Pominieto (juz zastosowano wczesniej): {label} w {path}")
        return
    for old in candidates:
        count = content.count(old)
        if count == 1:
            content = content.replace(old, new, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"OK: {label} -> {path}")
            return
    print(f"BLAD (zaden ze znanych wariantow nie pasuje): {label} w {path}")
    sys.exit(1)

# ---------------------------------------------------------------------------
# InvoiceHtmlPdfGenerator.kt — generateCorrection(): correctedItemIndex/
# correctedItemNewValue (jedna pozycja) -> correctedItems (mapa, wiele pozycji)
# ---------------------------------------------------------------------------
GEN = "app/src/main/java/com/example/fa_ksiegowy/InvoiceHtmlPdfGenerator.kt"

OLD_PARAMS = """        items: List<InvoiceItem> = emptyList(),
        vatRate: VatRate? = null,
        // Update: gdy faktura ma >1 pozycji i u\u017cytkownik wybra\u0142 JEDN\u0104 konkretn\u0105 pozycj\u0119 do
        // korekty (AddInvoiceCorrectionActivity) \u2014 correctedItemIndex wskazuje kt\u00f3r\u0105 (indeks
        // w `items`), correctedItemNewValue to jej nowa warto\u015b\u0107 (ilo\u015b\u0107*cena). Pozosta\u0142e
        // pozycje zostaj\u0105 BEZ ZMIAN zamiast (jak wcze\u015bniej) proporcjonalnego przeskalowania
        // wszystkich pozycji razem.
        correctedItemIndex: Int? = null,
        correctedItemNewValue: Double? = null
    ): ByteArray {"""

NEW_PARAMS = """        items: List<InvoiceItem> = emptyList(),
        vatRate: VatRate? = null,
        // Update 62: gdy faktura ma >1 pozycji i u\u017cytkownik wybra\u0142 JEDN\u0104 LUB WI\u0118CEJ
        // konkretnych pozycji do korekty (AddInvoiceCorrectionActivity) \u2014 correctedItems
        // to mapa indeks-w-`items` -> nowa warto\u015b\u0107 (ilo\u015b\u0107*cena) TEJ pozycji. Pozosta\u0142e
        // pozycje (nieobecne w mapie) zostaj\u0105 BEZ ZMIAN zamiast (jak wcze\u015bniej)
        // proporcjonalnego przeskalowania wszystkich pozycji razem. Pusta mapa = stare
        // zachowanie (korekta ca\u0142ej faktury, proporcjonalne przeskalowanie) \u2014 dotyczy
        // faktur z 0-1 pozycj\u0105.
        correctedItems: Map<Int, Double> = emptyMap()
    ): ByteArray {"""

str_replace_any(GEN, [OLD_PARAMS], NEW_PARAMS, "generateCorrection(): correctedItemIndex/correctedItemNewValue -> correctedItems")

OLD_COMMENT = """        // \"Przed korekt\u0105\" to zawsze oryginalne pozycje bez zmian. \"Po korekcie\": je\u015bli
        // wybrano konkretn\u0105 pozycj\u0119 (correctedItemIndex != null) \u2014 zmienia si\u0119 TYLKO ta
        // jedna pozycja, reszta zostaje identyczna; w przeciwnym razie (korekta ca\u0142ej
        // faktury, 0-1 pozycji) \u2014 stare zachowanie: proporcjonalne przeskalowanie."""

NEW_COMMENT = """        // \"Przed korekt\u0105\" to zawsze oryginalne pozycje bez zmian. \"Po korekcie\": je\u015bli
        // wybrano co najmniej jedn\u0105 pozycj\u0119 (correctedItems niepuste) \u2014 zmieniaj\u0105 si\u0119 TYLKO
        // zaznaczone pozycje (ka\u017cda wg swojej w\u0142asnej nowej warto\u015bci), reszta zostaje
        // identyczna; w przeciwnym razie (korekta ca\u0142ej faktury, 0-1 pozycji) \u2014 stare
        // zachowanie: proporcjonalne przeskalowanie."""

str_replace_any(GEN, [OLD_COMMENT], NEW_COMMENT, "komentarz Przed/Po korekcie")

OLD_AFTERROWS = """        val afterRows: List<Row> = when {
            correctedItemIndex != null && correctedItemNewValue != null && correctedItemIndex in items.indices -> {
                items.mapIndexed { idx, item ->
                    if (idx == correctedItemIndex) {
                        val newUnitPrice = if (item.quantity != 0.0) correctedItemNewValue / item.quantity else correctedItemNewValue
                        Row(item.name, item.quantity, newUnitPrice)
                    } else {
                        Row(item.name, item.quantity, item.unitPrice)
                    }
                }
            }
            items.isNotEmpty() -> {
                val scale = if (originalAmount != 0.0) correctedAmount / originalAmount else 1.0
                items.map { Row(it.name, it.quantity, it.unitPrice * scale) }
            }
            else -> listOf(Row(fallbackLabel, 1.0, correctedAmount))
        }"""

NEW_AFTERROWS = """        val afterRows: List<Row> = when {
            correctedItems.isNotEmpty() -> {
                items.mapIndexed { idx, item ->
                    val newValue = correctedItems[idx]
                    if (newValue != null) {
                        val newUnitPrice = if (item.quantity != 0.0) newValue / item.quantity else newValue
                        Row(item.name, item.quantity, newUnitPrice)
                    } else {
                        Row(item.name, item.quantity, item.unitPrice)
                    }
                }
            }
            items.isNotEmpty() -> {
                val scale = if (originalAmount != 0.0) correctedAmount / originalAmount else 1.0
                items.map { Row(it.name, it.quantity, it.unitPrice * scale) }
            }
            else -> listOf(Row(fallbackLabel, 1.0, correctedAmount))
        }"""

str_replace_any(GEN, [OLD_AFTERROWS], NEW_AFTERROWS, "afterRows: obsluga wielu correctedItems")

# ---------------------------------------------------------------------------
# invoice_template.html — plynne pojawienie fal (mask-image gradient na
# sztucznie przycietych krawedziach obrazkow .waves-*)
# ---------------------------------------------------------------------------
TPL = "app/src/main/assets/invoice_template.html"

OLD_WAVES = """  .waves-top{
    position:absolute; top:0; right:0; width:56.2mm; height:54.9mm;
    opacity:1; pointer-events:none; z-index:0; object-fit:cover;
  }
  .waves-bottom-left{
    position:absolute; bottom:0; left:0; width:105.85mm; height:64.6mm;
    opacity:1; pointer-events:none; z-index:0; object-fit:cover;
  }
  .waves-bottom-right{
    position:absolute; bottom:0; right:0; width:105.85mm; height:64.6mm;
    opacity:1; pointer-events:none; z-index:0; object-fit:cover;
  }"""

NEW_WAVES = """  .waves-top{
    position:absolute; top:0; right:0; width:56.2mm; height:54.9mm;
    opacity:1; pointer-events:none; z-index:0; object-fit:cover;
    /* Update 62: lewa kraw\u0119d\u017a tego obrazka to sztuczne, wewn\u0119trzne przyci\u0119cie (prawa
       i g\u00f3rna kraw\u0119d\u017a pokrywaj\u0105 si\u0119 z prawdziw\u0105 kraw\u0119dzi\u0105 strony) \u2014 bez maski linie
       urywa\u0142y si\u0119 tam nagle, w pe\u0142nym kryciu. Maska rozmywa je do przezroczysto\u015bci w
       stron\u0119 lewej kraw\u0119dzi, daj\u0105c p\u0142ynne pojawienie si\u0119 zamiast uci\u0119cia. */
    -webkit-mask-image: linear-gradient(to right, transparent 0%, #000 32%);
    mask-image: linear-gradient(to right, transparent 0%, #000 32%);
  }
  .waves-bottom-left{
    position:absolute; bottom:0; left:0; width:105.85mm; height:64.6mm;
    opacity:1; pointer-events:none; z-index:0; object-fit:cover;
    /* Update 62: g\u00f3rna i prawa kraw\u0119d\u017a to sztuczne przyci\u0119cie (dolna i lewa pokrywaj\u0105
       si\u0119 z kraw\u0119dzi\u0105 strony) \u2014 rozmycie w stron\u0119 g\u00f3rnego-prawego rogu. */
    -webkit-mask-image: linear-gradient(to top right, #000 55%, transparent 100%);
    mask-image: linear-gradient(to top right, #000 55%, transparent 100%);
  }
  .waves-bottom-right{
    position:absolute; bottom:0; right:0; width:105.85mm; height:64.6mm;
    opacity:1; pointer-events:none; z-index:0; object-fit:cover;
    /* Update 62: g\u00f3rna i lewa kraw\u0119d\u017a to sztuczne przyci\u0119cie (dolna i prawa pokrywaj\u0105
       si\u0119 z kraw\u0119dzi\u0105 strony) \u2014 rozmycie w stron\u0119 g\u00f3rnego-lewego rogu. */
    -webkit-mask-image: linear-gradient(to top left, #000 55%, transparent 100%);
    mask-image: linear-gradient(to top left, #000 55%, transparent 100%);
  }"""

str_replace_any(TPL, [OLD_WAVES], NEW_WAVES, "mask-image fade dla .waves-top/.waves-bottom-left/.waves-bottom-right")

# ---------------------------------------------------------------------------
# strings.xml (en / pl / ru) — nowe klucze dla wyboru wielu pozycji
# ---------------------------------------------------------------------------
LOCALES = {
    "app/src/main/res/values/strings.xml": {
        "hint_old": '    <string name="correction_item_picker_hint">Item to correct</string>',
        "hint_new": '    <string name="correction_item_picker_hint">Items to correct</string>',
        "insert_new": """    <string name="correction_pick_items_button">Choose items</string>
    <string name="correction_pick_items_dialog_title">Select items to correct</string>
    <string name="correction_pick_items_confirm">Apply</string>
    <string name="correction_no_items_selected_hint">No items selected yet</string>
    <string name="correction_no_items_selected_error">Select at least one item to correct</string>""",
    },
    "app/src/main/res/values-pl/strings.xml": {
        "hint_old": '    <string name="correction_item_picker_hint">Pozycja do korekty</string>',
        "hint_new": '    <string name="correction_item_picker_hint">Pozycje do korekty</string>',
        "insert_new": """    <string name="correction_pick_items_button">Wybierz pozycje</string>
    <string name="correction_pick_items_dialog_title">Wybierz pozycje do korekty</string>
    <string name="correction_pick_items_confirm">Zastosuj</string>
    <string name="correction_no_items_selected_hint">Nie wybrano jeszcze \u017cadnej pozycji</string>
    <string name="correction_no_items_selected_error">Wybierz przynajmniej jedn\u0105 pozycj\u0119 do korekty</string>""",
    },
    "app/src/main/res/values-ru/strings.xml": {
        "hint_old": '    <string name="correction_item_picker_hint">\u041f\u043e\u0437\u0438\u0446\u0438\u044f \u0434\u043b\u044f \u043a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0438</string>',
        "hint_new": '    <string name="correction_item_picker_hint">\u041f\u043e\u0437\u0438\u0446\u0438\u0438 \u0434\u043b\u044f \u043a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0438</string>',
        "insert_new": """    <string name="correction_pick_items_button">\u0412\u044b\u0431\u0440\u0430\u0442\u044c \u043f\u043e\u0437\u0438\u0446\u0438\u0438</string>
    <string name="correction_pick_items_dialog_title">\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u043f\u043e\u0437\u0438\u0446\u0438\u0438 \u0434\u043b\u044f \u043a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0438</string>
    <string name="correction_pick_items_confirm">\u041f\u0440\u0438\u043c\u0435\u043d\u0438\u0442\u044c</string>
    <string name="correction_no_items_selected_hint">\u041f\u043e\u043a\u0430 \u043d\u0435 \u0432\u044b\u0431\u0440\u0430\u043d\u043e \u043d\u0438 \u043e\u0434\u043d\u043e\u0439 \u043f\u043e\u0437\u0438\u0446\u0438\u0438</string>
    <string name="correction_no_items_selected_error">\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0445\u043e\u0442\u044f \u0431\u044b \u043e\u0434\u043d\u0443 \u043f\u043e\u0437\u0438\u0446\u0438\u044e \u0434\u043b\u044f \u043a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0438</string>""",
    },
}

for path, spec in LOCALES.items():
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if 'name="correction_pick_items_button"' in content:
        print(f"Pominieto (juz zastosowano wczesniej): nowe klucze correction_pick_items_* w {path}")
        continue
    if spec["hint_old"] not in content:
        print(f"BLAD: nie znaleziono oczekiwanej linii correction_item_picker_hint w {path}")
        sys.exit(1)
    replacement = spec["hint_new"] + "\n" + spec["insert_new"]
    content = content.replace(spec["hint_old"], replacement, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: nowe klucze correction_pick_items_* -> {path}")

print("")
print("Wszystkie punktowe patche zastosowane pomyslnie.")
PYEOF

echo ""
echo "Gotowe."
echo ""
echo "Co zrobic dalej (Termux):"
echo "  git add -A"
echo "  git commit -m \"update 62: korekta wielu pozycji naraz (dialog w stylu appki) + plynne pojawienie fal na PDF\""
echo "  git push origin main"
