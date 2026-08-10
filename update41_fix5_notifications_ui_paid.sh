#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Update 41 fix 5: язык уведомлений, тап по уведомлению, приход/расход UI, склад только для продаж, +/- в позициях, отметить фактуру оплаченной ==="
echo ""
echo "Не входит в этот скрипт: 'korekty faktur' (корректировочные фактуры) — это отдельная"
echo "крупная фича (новая таблица в базе, новый экран, новый шаблон PDF), сделаю отдельным"
echo "update42, чтобы не смешивать с этими точечными правками."
echo ""

JAVA_DIR="app/src/main/java/com/example/fa_ksiegowy"
LAYOUT_DIR="app/src/main/res/layout"

if [ ! -f "settings.gradle" ] || [ ! -f "$JAVA_DIR/LocaleHelper.kt" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy (там, где settings.gradle)"
    exit 1
fi

BACKUP_DIR=".update41_fix5_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR/$JAVA_DIR" "$BACKUP_DIR/$LAYOUT_DIR" "$BACKUP_DIR/app/src/main/res/values" "$BACKUP_DIR/app/src/main/res/values-ru" "$BACKUP_DIR/app/src/main/res/values-pl"
for f in LimitsNotificationWorker.kt InvoiceReminderWorker.kt StockNotificationWorker.kt AddEntryActivity.kt AddInvoiceActivity.kt SelectProductsActivity.kt InvoiceHistoryActivity.kt InvoiceAdapter.kt; do
    cp "$JAVA_DIR/$f" "$BACKUP_DIR/$JAVA_DIR/$f"
done
for f in item_product_select.xml item_invoice.xml; do
    cp "$LAYOUT_DIR/$f" "$BACKUP_DIR/$LAYOUT_DIR/$f"
done
cp app/src/main/res/values/strings.xml "$BACKUP_DIR/app/src/main/res/values/strings.xml"
cp app/src/main/res/values-ru/strings.xml "$BACKUP_DIR/app/src/main/res/values-ru/strings.xml"
cp app/src/main/res/values-pl/strings.xml "$BACKUP_DIR/app/src/main/res/values-pl/strings.xml"
echo "--- Бэкап сохранён в $BACKUP_DIR ---"

# ---------------------------------------------------------------------------
# 1) Язык уведомлений = язык, выбранный в приложении (а не системный язык телефона)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX5_LOCALE'
import re

comment = (
    "            // Уведомления должны быть на языке, выбранном В ПРИЛОЖЕНИИ (LocaleHelper),\n"
    "            // а не на системном языке телефона — раньше applicationContext.getString(...)\n"
    "            // брал системную локаль напрямую, из-за чего уведомления могли отличаться\n"
    "            // от языка интерфейса приложения.\n"
    "            val ctx = LocaleHelper.applyLocale(applicationContext)\n"
)

# Два файла используют паттерн "return try {", один (LimitsNotificationWorker) — просто "try {".
files_return_try = [
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceReminderWorker.kt",
    "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt",
]
for path in files_return_try:
    text = open(path, encoding="utf-8").read()
    old = "    override suspend fun doWork(): Result {\n        return try {\n"
    if old not in text:
        raise SystemExit(f"ANCHOR NOT FOUND (return try) in {path} — возможно, уже пофикшено")
    new = "    override suspend fun doWork(): Result {\n        return try {\n" + comment
    text = text.replace(old, new, 1)
    count_before = text.count("applicationContext.getString(")
    text = text.replace("applicationContext.getString(", "ctx.getString(")
    open(path, "w", encoding="utf-8").write(text)
    print(f"OK: {path} ({count_before} мест заменено на локализованный контекст)")

path = "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt"
text = open(path, encoding="utf-8").read()
old = "    override suspend fun doWork(): Result {\n        try {\n"
if old not in text:
    raise SystemExit(f"ANCHOR NOT FOUND (try) in {path} — возможно, уже пофикшено")
new = "    override suspend fun doWork(): Result {\n        try {\n" + comment
text = text.replace(old, new, 1)
count_before = text.count("applicationContext.getString(")
text = text.replace("applicationContext.getString(", "ctx.getString(")
open(path, "w", encoding="utf-8").write(text)
print(f"OK: {path} ({count_before} мест заменено на локализованный контекст)")
PYEOF_U41FIX5_LOCALE

# ---------------------------------------------------------------------------
# 2) Тап по уведомлению открывает нужный экран (для фактур — историю фактур)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX5_TAPINTENT'
path = "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt"
text = open(path, encoding="utf-8").read()

old_imports = "import android.Manifest\nimport android.app.NotificationChannel\n"
new_imports = "import android.Manifest\nimport android.app.NotificationChannel\nimport android.app.PendingIntent\nimport android.content.Intent\n"
if old_imports not in text:
    raise SystemExit("ANCHOR 1 NOT FOUND in LimitsNotificationWorker.kt (imports)")
text = text.replace(old_imports, new_imports, 1)

old_fn = '''        fun showNotification(context: Context, id: Int, title: String, text: String) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                if (!granted) return
            }
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .build()'''
new_fn = '''        fun showNotification(context: Context, id: Int, title: String, text: String, targetActivity: Class<*>? = null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                if (!granted) return
            }
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
            // Тап по уведомлению должен открывать соответствующий экран приложения —
            // раньше при тапе ничего не происходило, так как contentIntent не задавался.
            if (targetActivity != null) {
                val openIntent = Intent(context, targetActivity).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, id, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                builder.setContentIntent(pendingIntent)
            }
            val notification = builder.build()'''
if old_fn not in text:
    raise SystemExit("ANCHOR 2 NOT FOUND in LimitsNotificationWorker.kt (showNotification body)")
text = text.replace(old_fn, new_fn, 1)
open(path, "w", encoding="utf-8").write(text)
print("OK: app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt (showNotification открывает нужный экран по тапу)")
PYEOF_U41FIX5_TAPINTENT

python3 - << 'PYEOF_U41FIX5_INVOICE_NOTIFY'
path = "app/src/main/java/com/example/fa_ksiegowy/InvoiceReminderWorker.kt"
text = open(path, encoding="utf-8").read()

old_calls = '''            val pending = dao.getAll().filter { it.status == InvoiceStatus.PENDING && it.dueDateMillis != null }
            for (inv in pending) {
                val due = inv.dueDateMillis ?: continue
                when {
                    due < now -> notifyOnce(
                        prefs, "invoice_overdue_${inv.id}",
                        ctx.getString(R.string.notif_invoice_overdue_title),
                        ctx.getString(R.string.notif_invoice_overdue_text, inv.buyerName, inv.invoiceNumber)
                    )
                    due - now <= threeDaysMs -> notifyOnce(
                        prefs, "invoice_due_soon_${inv.id}",
                        ctx.getString(R.string.notif_invoice_due_soon_title),
                        ctx.getString(R.string.notif_invoice_due_soon_text, inv.buyerName, inv.invoiceNumber)
                    )
                }
            }'''
new_calls = '''            val pending = dao.getAll().filter { it.status == InvoiceStatus.PENDING && it.dueDateMillis != null }
            for (inv in pending) {
                val due = inv.dueDateMillis ?: continue
                when {
                    due < now -> notifyOnce(
                        prefs, "invoice_overdue_${inv.id}",
                        ctx.getString(R.string.notif_invoice_overdue_title),
                        ctx.getString(R.string.notif_invoice_overdue_text, inv.buyerName, inv.invoiceNumber),
                        InvoiceHistoryActivity::class.java
                    )
                    due - now <= threeDaysMs -> notifyOnce(
                        prefs, "invoice_due_soon_${inv.id}",
                        ctx.getString(R.string.notif_invoice_due_soon_title),
                        ctx.getString(R.string.notif_invoice_due_soon_text, inv.buyerName, inv.invoiceNumber),
                        InvoiceHistoryActivity::class.java
                    )
                }
            }'''
if old_calls not in text:
    raise SystemExit("ANCHOR 1 NOT FOUND in InvoiceReminderWorker.kt (notifyOnce calls) — возможно, уже пофикшено")
text = text.replace(old_calls, new_calls, 1)

old_notifyonce = '''    private fun notifyOnce(prefs: android.content.SharedPreferences, key: String, title: String, text: String) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text)
    }'''
new_notifyonce = '''    private fun notifyOnce(
        prefs: android.content.SharedPreferences, key: String, title: String, text: String,
        targetActivity: Class<*>? = null
    ) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text, targetActivity)
    }'''
if old_notifyonce not in text:
    raise SystemExit("ANCHOR 2 NOT FOUND in InvoiceReminderWorker.kt (notifyOnce fun) — возможно, уже пофикшено")
text = text.replace(old_notifyonce, new_notifyonce, 1)

open(path, "w", encoding="utf-8").write(text)
print("OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceReminderWorker.kt (тап открывает историю фактур)")
PYEOF_U41FIX5_INVOICE_NOTIFY

# ---------------------------------------------------------------------------
# 3) AddEntryActivity.kt — "Dołącz paragon"/"Skanuj paragon" только для Wydatek,
#    и явное выделение выбранного Przychód/Wydatek
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX5_ADDENTRY'
path = "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt"
text = open(path, encoding="utf-8").read()
old = '''    private fun updateTypeToggleUi() {
        val income = findViewById<Button>(R.id.btn_type_income)
        val expense = findViewById<Button>(R.id.btn_type_expense)
        income.setBackgroundResource(if (currentIsIncome) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
        expense.setBackgroundResource(if (!currentIsIncome) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
        // Сканирование чека имеет смысл только для расходов (чек подтверждает трату).
        findViewById<Button>(R.id.btn_scan_receipt).visibility = if (currentIsIncome) View.GONE else View.VISIBLE
    }'''
new = '''    private fun updateTypeToggleUi() {
        val income = findViewById<Button>(R.id.btn_type_income)
        val expense = findViewById<Button>(R.id.btn_type_expense)
        // Явное выделение выбранного варианта — тот же приём, что и для способа оплаты
        // на экране фактуры: яркий фон + белый жирный текст против приглушённого фона
        // и серого текста у невыбранного варианта.
        income.setBackgroundResource(if (currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        expense.setBackgroundResource(if (!currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        income.setTextColor(resources.getColor(if (currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        expense.setTextColor(resources.getColor(if (!currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        income.alpha = if (currentIsIncome) 1.0f else 0.75f
        expense.alpha = if (!currentIsIncome) 1.0f else 0.75f
        // Прикладывать/сканировать чек имеет смысл только для расходов (чек подтверждает трату).
        findViewById<Button>(R.id.btn_attach).visibility = if (currentIsIncome) View.GONE else View.VISIBLE
        findViewById<Button>(R.id.btn_scan_receipt).visibility = if (currentIsIncome) View.GONE else View.VISIBLE
    }'''
if old not in text:
    raise SystemExit("ANCHOR NOT FOUND in AddEntryActivity.kt — возможно, уже пофикшено")
text = text.replace(old, new, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_ADDENTRY
echo "OK: $JAVA_DIR/AddEntryActivity.kt (кнопки чека только для расхода + явное выделение приход/расход)"

# ---------------------------------------------------------------------------
# 4) AddInvoiceActivity.kt — "Dodaj towary z magazynu" только если Sprzedaż/Mieszana
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX5_ADDINVOICE'
path = "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt"
text = open(path, encoding="utf-8").read()

old = '''        loadSellerData()
        refreshCashLimit()
    }'''
new = '''        loadSellerData()
        refreshCashLimit()
        applyBusinessKindUi()
    }

    override fun onResume() {
        super.onResume()
        // Настройка "Тип деятельности" в Ustawieniach могла измениться, пока
        // пользователь был на другом экране — перепроверяем при каждом возврате.
        applyBusinessKindUi()
    }

    /** Кнопка "Dodaj towary z magazynu" видна только для Sprzedaż/Mieszana — для чистых
     *  Usługi склада нет, кнопка была бы просто непонятной и бесполезной. */
    private fun applyBusinessKindUi() {
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        findViewById<Button>(R.id.btn_add_warehouse_items).visibility =
            if (BusinessKindHelper.get(prefs).showsMagazin) View.VISIBLE else View.GONE
    }'''
if old not in text:
    raise SystemExit("ANCHOR NOT FOUND in AddInvoiceActivity.kt — возможно, уже пофикшено")
text = text.replace(old, new, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_ADDINVOICE
echo "OK: $JAVA_DIR/AddInvoiceActivity.kt (кнопка склада скрыта для Usługi)"

# ---------------------------------------------------------------------------
# 5) SelectProductsActivity.kt + item_product_select.xml — кнопки "−"/"+" для количества
# ---------------------------------------------------------------------------
cat > "$LAYOUT_DIR/item_product_select.xml" << 'EOF_U41FIX5_ITEM_PRODUCT_SELECT_XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:background="@drawable/card_bg"
    android:padding="10dp"
    android:layout_marginBottom="6dp"
    android:gravity="center_vertical">

    <CheckBox
        android:id="@+id/cb_select"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"/>

    <TextView
        android:id="@+id/tv_select_name"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_marginStart="8dp"
        android:textColor="@color/text_primary"
        android:textSize="14sp"/>

    <TextView
        android:id="@+id/btn_qty_minus"
        android:layout_width="34dp"
        android:layout_height="34dp"
        android:text="−"
        android:textColor="@color/accent_cyan"
        android:textSize="18sp"
        android:textStyle="bold"
        android:gravity="center"
        android:clickable="true"
        android:focusable="true"
        android:background="?android:attr/selectableItemBackgroundBorderless"/>

    <EditText
        android:id="@+id/et_select_qty"
        android:layout_width="48dp"
        android:layout_height="wrap_content"
        android:layout_marginStart="2dp"
        android:layout_marginEnd="2dp"
        android:background="@drawable/input_field_bg"
        android:textColor="@color/text_primary"
        android:gravity="center"
        android:inputType="numberDecimal"/>

    <TextView
        android:id="@+id/btn_qty_plus"
        android:layout_width="34dp"
        android:layout_height="34dp"
        android:text="+"
        android:textColor="@color/accent_cyan"
        android:textSize="18sp"
        android:textStyle="bold"
        android:gravity="center"
        android:clickable="true"
        android:focusable="true"
        android:background="?android:attr/selectableItemBackgroundBorderless"/>

</LinearLayout>
EOF_U41FIX5_ITEM_PRODUCT_SELECT_XML
echo "OK: $LAYOUT_DIR/item_product_select.xml (добавлены кнопки −/+)"

python3 - << 'PYEOF_U41FIX5_SELECTPRODUCTS'
path = "app/src/main/java/com/example/fa_ksiegowy/SelectProductsActivity.kt"
text = open(path, encoding="utf-8").read()

old = '''            tvName.text = "${p.name} (${formatNum(p.quantity)} ${p.unit} ${getString(R.string.in_stock_suffix)})"
            etQty.setText("1")
            etQty.isEnabled = false

            cb.setOnCheckedChangeListener { _, isChecked ->'''
new = '''            tvName.text = "${p.name} (${formatNum(p.quantity)} ${p.unit} ${getString(R.string.in_stock_suffix)})"
            etQty.setText("1")
            etQty.isEnabled = false

            val btnMinus = row.findViewById<TextView>(R.id.btn_qty_minus)
            val btnPlus = row.findViewById<TextView>(R.id.btn_qty_plus)
            // "+" на невыбранном товаре сначала просто отмечает его (количество остаётся 1),
            // повторные нажатия увеличивают на 1 — так поведение интуитивно совпадает с
            // "добавить ещё одну единицу этого товара". "−" на количестве 1 снимает отметку.
            btnPlus.setOnClickListener {
                if (!cb.isChecked) {
                    cb.isChecked = true
                } else {
                    val cur = etQty.text.toString().toDoubleOrNull() ?: 1.0
                    etQty.setText(formatNum(cur + 1))
                }
            }
            btnMinus.setOnClickListener {
                if (!cb.isChecked) return@setOnClickListener
                val cur = etQty.text.toString().toDoubleOrNull() ?: 1.0
                if (cur <= 1.0) {
                    cb.isChecked = false
                } else {
                    etQty.setText(formatNum(cur - 1))
                }
            }

            cb.setOnCheckedChangeListener { _, isChecked ->'''
if old not in text:
    raise SystemExit("ANCHOR NOT FOUND in SelectProductsActivity.kt — возможно, уже пофикшено")
text = text.replace(old, new, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_SELECTPRODUCTS
echo "OK: $JAVA_DIR/SelectProductsActivity.kt (кнопки −/+ работают)"

# ---------------------------------------------------------------------------
# 6) Отметить фактуру оплаченной прямо из истории (без пересоздания PDF)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX5_ITEM_INVOICE_XML'
path = "app/src/main/res/layout/item_invoice.xml"
text = open(path, encoding="utf-8").read()
old = '''    <TextView
        android:id="@+id/btn_delete_invoice"'''
new = '''    <TextView
        android:id="@+id/btn_mark_paid"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="10dp"
        android:padding="6dp"
        android:text="✓"
        android:textColor="#4CD964"
        android:textSize="16sp"
        android:textStyle="bold"
        android:clickable="true"
        android:focusable="true"
        android:background="?android:attr/selectableItemBackgroundBorderless"
        android:visibility="gone"/>

    <TextView
        android:id="@+id/btn_delete_invoice"'''
if old not in text:
    raise SystemExit("ANCHOR NOT FOUND in item_invoice.xml — возможно, уже пофикшено")
text = text.replace(old, new, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_ITEM_INVOICE_XML
echo "OK: $LAYOUT_DIR/item_invoice.xml (добавлена кнопка ✓ 'отметить оплаченной')"

python3 - << 'PYEOF_U41FIX5_INVOICE_ADAPTER'
path = "app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt"
text = open(path, encoding="utf-8").read()

old_ctor = '''class InvoiceAdapter(
    initialItems: List<Invoice> = emptyList(),
    private val onItemClick: (Invoice) -> Unit = {},
    private val onDeleteClick: (Invoice) -> Unit = {}
) : RecyclerView.Adapter<InvoiceAdapter.VH>() {'''
new_ctor = '''class InvoiceAdapter(
    initialItems: List<Invoice> = emptyList(),
    private val onItemClick: (Invoice) -> Unit = {},
    private val onDeleteClick: (Invoice) -> Unit = {},
    private val onMarkPaidClick: (Invoice) -> Unit = {}
) : RecyclerView.Adapter<InvoiceAdapter.VH>() {'''
if old_ctor not in text:
    raise SystemExit("ANCHOR 1 NOT FOUND in InvoiceAdapter.kt (constructor) — возможно, уже пофикшено")
text = text.replace(old_ctor, new_ctor, 1)

old_vh = '''        val btnDelete = view.findViewById<TextView>(R.id.btn_delete_invoice)
    }'''
new_vh = '''        val btnDelete = view.findViewById<TextView>(R.id.btn_delete_invoice)
        val btnMarkPaid = view.findViewById<TextView>(R.id.btn_mark_paid)
    }'''
if old_vh not in text:
    raise SystemExit("ANCHOR 2 NOT FOUND in InvoiceAdapter.kt (VH) — возможно, уже пофикшено")
text = text.replace(old_vh, new_vh, 1)

old_bind = '''        holder.itemView.setOnClickListener { onItemClick(inv) }
        holder.btnDelete.setOnClickListener { onDeleteClick(inv) }
    }'''
new_bind = '''        holder.btnMarkPaid.visibility = if (inv.status == InvoiceStatus.PENDING) View.VISIBLE else View.GONE
        holder.itemView.setOnClickListener { onItemClick(inv) }
        holder.btnDelete.setOnClickListener { onDeleteClick(inv) }
        holder.btnMarkPaid.setOnClickListener { onMarkPaidClick(inv) }
    }'''
if old_bind not in text:
    raise SystemExit("ANCHOR 3 NOT FOUND in InvoiceAdapter.kt (bind) — возможно, уже пофикшено")
text = text.replace(old_bind, new_bind, 1)

open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_INVOICE_ADAPTER
echo "OK: $JAVA_DIR/InvoiceAdapter.kt (кнопка 'отметить оплаченной' видна для неоплаченных)"

python3 - << 'PYEOF_U41FIX5_INVOICE_HISTORY'
path = "app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt"
text = open(path, encoding="utf-8").read()

old_ctor = '''        adapter = InvoiceAdapter(
            onItemClick = { invoice -> openInvoicePdf(invoice) },
            onDeleteClick = { invoice -> confirmDelete(invoice) }
        )'''
new_ctor = '''        adapter = InvoiceAdapter(
            onItemClick = { invoice -> openInvoicePdf(invoice) },
            onDeleteClick = { invoice -> confirmDelete(invoice) },
            onMarkPaidClick = { invoice -> confirmMarkPaid(invoice) }
        )'''
if old_ctor not in text:
    raise SystemExit("ANCHOR 1 NOT FOUND in InvoiceHistoryActivity.kt (adapter ctor) — возможно, уже пофикшено")
text = text.replace(old_ctor, new_ctor, 1)

old_confirm_delete = '''    private fun confirmDelete(invoice: Invoice) {'''
new_methods = '''    /** Меняет статус на "оплачено" (сегодняшней датой) прямо из истории — например,
     *  когда клиент оплатил после срока и фактура была просроченной/ожидающей оплаты.
     *  ВАЖНО: меняется только запись в базе (список, фильтры, отчёты) — уже сохранённый
     *  PDF-файл при этом не перегенерируется и продолжит показывать прежний статус. */
    private fun confirmMarkPaid(invoice: Invoice) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.invoice_mark_paid_confirm_title))
            .setMessage(getString(R.string.invoice_mark_paid_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).invoiceDao().update(
                        invoice.copy(status = InvoiceStatus.PAID, paymentDateMillis = System.currentTimeMillis())
                    )
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@InvoiceHistoryActivity, getString(R.string.invoice_marked_paid_toast), Toast.LENGTH_SHORT).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    private fun confirmDelete(invoice: Invoice) {'''
if old_confirm_delete not in text:
    raise SystemExit("ANCHOR 2 NOT FOUND in InvoiceHistoryActivity.kt (confirmDelete) — возможно, уже пофикшено")
text = text.replace(old_confirm_delete, new_methods, 1)

open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_INVOICE_HISTORY
echo "OK: $JAVA_DIR/InvoiceHistoryActivity.kt (отметка 'оплачено' сохраняется в базу)"

# ---------------------------------------------------------------------------
# 7) Новые строки
# ---------------------------------------------------------------------------
python3 - << 'PYEOF_U41FIX5_STRINGS_BASE'
path = "app/src/main/res/values/strings.xml"
text = open(path, encoding="utf-8").read()
addition = '''
    <!-- Update 41 fix 5 -->
    <string name="invoice_mark_paid_confirm_title">Mark as paid?</string>
    <string name="invoice_mark_paid_confirm_message">This sets the invoice status to paid today. The already generated PDF file won\\'t be changed.</string>
    <string name="invoice_marked_paid_toast">Invoice marked as paid</string>
</resources>'''
if not text.rstrip().endswith("</resources>"):
    raise SystemExit("Unexpected end of values/strings.xml")
text = text.rstrip()[:-len("</resources>")] + addition + "\n"
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_STRINGS_BASE
echo "OK: app/src/main/res/values/strings.xml"

python3 - << 'PYEOF_U41FIX5_STRINGS_RU'
path = "app/src/main/res/values-ru/strings.xml"
text = open(path, encoding="utf-8").read()
addition = '''
    <!-- Update 41 fix 5 -->
    <string name="invoice_mark_paid_confirm_title">Отметить как оплаченную?</string>
    <string name="invoice_mark_paid_confirm_message">Статус фактуры изменится на «оплачена» сегодняшним числом. Уже сохранённый PDF-файл при этом не изменится.</string>
    <string name="invoice_marked_paid_toast">Фактура отмечена как оплаченная</string>
</resources>'''
if not text.rstrip().endswith("</resources>"):
    raise SystemExit("Unexpected end of values-ru/strings.xml")
text = text.rstrip()[:-len("</resources>")] + addition + "\n"
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_STRINGS_RU
echo "OK: app/src/main/res/values-ru/strings.xml"

python3 - << 'PYEOF_U41FIX5_STRINGS_PL'
path = "app/src/main/res/values-pl/strings.xml"
text = open(path, encoding="utf-8").read()
addition = '''
    <!-- Update 41 fix 5 -->
    <string name="invoice_mark_paid_confirm_title">Oznaczyć jako opłaconą?</string>
    <string name="invoice_mark_paid_confirm_message">Status faktury zmieni się na „opłacona” z dzisiejszą datą. Już zapisany plik PDF nie zostanie zmieniony.</string>
    <string name="invoice_marked_paid_toast">Faktura oznaczona jako opłacona</string>
</resources>'''
if not text.rstrip().endswith("</resources>"):
    raise SystemExit("Unexpected end of values-pl/strings.xml")
text = text.rstrip()[:-len("</resources>")] + addition + "\n"
open(path, "w", encoding="utf-8").write(text)
PYEOF_U41FIX5_STRINGS_PL
echo "OK: app/src/main/res/values-pl/strings.xml"

echo ""
echo "=== Готово. Дальше: ==="
echo "git add -A && git commit -m 'fix: notification locale+tap intent, income/expense UI, warehouse button visibility, qty stepper, mark invoice paid' && git push"
