#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 27: история/список выставленных счетов (Faktury/Rachunki) ==="
echo "Добавляет отдельный экран со списком всех счетов (дата, покупатель, № документа,"
echo "способ оплаты, сумма). Тап по строке открывает сохранённый PDF. Доступ — кнопка"
echo "\"История\" на экране выставления счёта."
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy-main (там, где settings.gradle)"
    exit 1
fi

if [ ! -f "app/src/main/java/com/example/fa_ksiegowy/Invoice.kt" ]; then
    echo "!!! Не найден Invoice.kt — сначала примени update_project-26-invoices.sh"
    exit 1
fi

BACKUP_DIR=".update27_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/AndroidManifest.xml" \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" \
    "app/src/main/res/layout/activity_add_invoice.xml" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/res/values-ru/strings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Бэкап изменяемых файлов сохранён в $BACKUP_DIR ---"

# ============================================================
# 1) Новые файлы
# ============================================================

mkdir -p "$(dirname "app/src/main/res/layout/item_invoice.xml")"
cat > app/src/main/res/layout/item_invoice.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ITEM_INVOICE_XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:background="@drawable/card_bg"
    android:padding="12dp"
    android:layout_marginBottom="8dp"
    android:gravity="center_vertical">

    <TextView
        android:id="@+id/tv_invoice_date"
        android:layout_width="64dp"
        android:layout_height="wrap_content"
        android:textColor="@color/text_secondary"
        android:textSize="12sp"/>

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_marginStart="8dp"
        android:orientation="vertical">

        <TextView
            android:id="@+id/tv_invoice_buyer"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_primary"
            android:textSize="14sp"
            android:maxLines="1"
            android:ellipsize="end"/>

        <TextView
            android:id="@+id/tv_invoice_meta"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:maxLines="1"
            android:ellipsize="end"/>
    </LinearLayout>

    <TextView
        android:id="@+id/tv_invoice_amount"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="8dp"
        android:gravity="end"
        android:minWidth="72dp"
        android:textColor="@color/text_primary"
        android:textSize="16sp"
        android:textStyle="bold"/>

</LinearLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ITEM_INVOICE_XML
echo "OK: app/src/main/res/layout/item_invoice.xml"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEADAPTER_KT'
package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Список выставленных счетов/фактур — используется на экране InvoiceHistoryActivity. */
class InvoiceAdapter(
    private val items: List<Invoice>,
    private val onItemClick: (Invoice) -> Unit = {}
) : RecyclerView.Adapter<InvoiceAdapter.VH>() {
    private val dateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvDate = view.findViewById<TextView>(R.id.tv_invoice_date)
        val tvBuyer = view.findViewById<TextView>(R.id.tv_invoice_buyer)
        val tvMeta = view.findViewById<TextView>(R.id.tv_invoice_meta)
        val tvAmount = view.findViewById<TextView>(R.id.tv_invoice_amount)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_invoice, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val inv = items[position]
        val context = holder.itemView.context
        holder.tvDate.text = dateFmt.format(Date(inv.issueDateMillis))
        holder.tvBuyer.text = inv.buyerName
        holder.tvMeta.text = "№${inv.invoiceNumber} · " + context.getString(inv.paymentMethod.labelResId)
        holder.tvAmount.text = String.format(Locale.getDefault(), "%.2f", inv.amount)
        holder.itemView.setOnClickListener { onItemClick(inv) }
    }

    override fun getItemCount(): Int = items.size
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEADAPTER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt"

mkdir -p "$(dirname "app/src/main/res/layout/activity_invoice_history.xml")"
cat > app/src/main/res/layout/activity_invoice_history.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_INVOICE_HISTORY_XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:paddingStart="24dp"
    android:paddingEnd="24dp"
    android:paddingTop="36dp"
    android:paddingBottom="16dp">

    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/invoice_history_title"
        android:textSize="22sp"
        android:textStyle="bold"
        android:textColor="@color/accent_cyan"
        android:layout_marginBottom="14dp"/>

    <TextView
        android:id="@+id/tv_no_invoices"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/no_invoices"
        android:textColor="@color/text_secondary"
        android:textSize="15sp"
        android:visibility="gone"
        android:layout_marginTop="40dp"
        android:gravity="center"/>

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/rv_invoices"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:clipToPadding="false"/>

</LinearLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_INVOICE_HISTORY_XML
echo "OK: app/src/main/res/layout/activity_invoice_history.xml"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYACTIVITY_KT'
package com.example.fa_ksiegowy

import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Экран истории всех выставленных счетов/фактур (Faktura imienna / Rachunek).
 * Тап по строке открывает сохранённый PDF в системном просмотрщике; если
 * подходящее приложение не найдено — показываем путь к папке текстом.
 */
class InvoiceHistoryActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_invoice_history)

        findViewById<RecyclerView>(R.id.rv_invoices).layoutManager = LinearLayoutManager(this)
        loadData()
    }

    override fun onResume() {
        super.onResume()
        // Список могут пополнить новой записью, вернувшись с экрана выставления счёта.
        loadData()
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            val allInvoices = AppDatabase.getInstance(applicationContext).invoiceDao().getAll()
            withContext(Dispatchers.Main) {
                findViewById<RecyclerView>(R.id.rv_invoices).adapter = InvoiceAdapter(allInvoices) { invoice ->
                    openInvoicePdf(invoice)
                }
                findViewById<TextView>(R.id.tv_no_invoices).visibility =
                    if (allInvoices.isEmpty()) View.VISIBLE else View.GONE
            }
        }
    }

    private fun openInvoicePdf(invoice: Invoice) {
        try {
            startActivity(InvoiceFileStorage.viewIntent(Uri.parse(invoice.pdfFilePath)))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, getString(R.string.open_folder_error, InvoiceFileStorage.displayFolderPath), Toast.LENGTH_LONG).show()
        }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt"


# ============================================================
# 2) Точечные правки существующих файлов (безопасно перезапускать)
# ============================================================

echo ""
echo "--- Правки существующих файлов ---"

# --- 2.1 AndroidManifest.xml: регистрируем InvoiceHistoryActivity ---
python3 - "app/src/main/AndroidManifest.xml" << 'EOF_PY_MANIFEST'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "InvoiceHistoryActivity" in content:
    print("OK (уже применено): %s" % path)
else:
    anchor = '        <activity android:name=".AddInvoiceActivity" android:exported="false" />\n'
    if anchor not in content:
        print("!!! Не найден якорь AddInvoiceActivity в %s (сначала примени update_project-26)" % path)
        sys.exit(1)
    new_line = '        <activity android:name=".InvoiceHistoryActivity" android:exported="false" />\n'
    content = content.replace(anchor, anchor + new_line, 1)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: %s -> добавлена InvoiceHistoryActivity" % path)
EOF_PY_MANIFEST

# --- 2.2 activity_add_invoice.xml: кнопка "История" под заголовком формы ---
python3 - "app/src/main/res/layout/activity_add_invoice.xml" << 'EOF_PY_LAYOUT'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "btn_invoice_history" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

anchor = '''    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="12dp"
        android:layout_marginBottom="20dp"
        android:text="@string/invoice_form_title"
        android:textColor="@color/accent_cyan"
        android:textSize="24sp"
        android:textStyle="bold"/>
'''
if anchor not in content:
    print("!!! Не найден заголовок формы счёта в %s" % path)
    sys.exit(1)

addition = anchor + '''
    <Button
        android:id="@+id/btn_invoice_history"
        android:layout_width="match_parent"
        android:layout_height="48dp"
        android:layout_marginBottom="16dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/invoice_history_title"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="14sp"/>
'''
content = content.replace(anchor, addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлена кнопка btn_invoice_history" % path)
EOF_PY_LAYOUT

# --- 2.3 AddInvoiceActivity.kt: обработчик кнопки "История" ---
python3 - "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" << 'EOF_PY_ADD'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "InvoiceHistoryActivity" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

anchor = '''        findViewById<Button>(R.id.btn_open_folder).setOnClickListener { openInvoicesFolder() }
'''
if anchor not in content:
    print("!!! Не найден якорь btn_open_folder в %s" % path)
    sys.exit(1)

addition = anchor + '''        findViewById<Button>(R.id.btn_invoice_history).setOnClickListener {
            startActivity(Intent(this, InvoiceHistoryActivity::class.java))
        }
'''
content = content.replace(anchor, addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлен обработчик btn_invoice_history" % path)
EOF_PY_ADD

echo "--- Правки применены ---"

# --- 2.4 strings.xml (EN/PL/RU): строки для истории счетов ---
echo "-- English: app/src/main/res/values/strings.xml --"
python3 - "app/src/main/res/values/strings.xml" << 'EOF_PY_STRINGS_EN'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "invoice_history_title" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''
    <!-- Invoice history -->
    <string name="invoice_history_title">Invoice history</string>
    <string name="no_invoices">No invoices yet</string>

</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки истории счетов" % path)
EOF_PY_STRINGS_EN

echo "-- Polski: app/src/main/res/values-pl/strings.xml --"
python3 - "app/src/main/res/values-pl/strings.xml" << 'EOF_PY_STRINGS_PL'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "invoice_history_title" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''
    <!-- Historia faktur -->
    <string name="invoice_history_title">Historia faktur</string>
    <string name="no_invoices">Nie wystawiono jeszcze żadnych faktur</string>

</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки истории счетов" % path)
EOF_PY_STRINGS_PL

echo "-- Русский: app/src/main/res/values-ru/strings.xml --"
python3 - "app/src/main/res/values-ru/strings.xml" << 'EOF_PY_STRINGS_RU'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "invoice_history_title" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''
    <!-- История счетов -->
    <string name="invoice_history_title">История счетов</string>
    <string name="no_invoices">Вы ещё не выставили ни одного счёта</string>

</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки истории счетов" % path)
EOF_PY_STRINGS_RU


echo ""
echo "=== Готово. Дальше вручную: ==="
echo "1) Пересобери APK:  ./gradlew assembleDebug"
echo "2) Проверь: на экране выставления счёта появилась кнопка \"История/Historia/History\","
echo "   она открывает список ранее выставленных счетов, тап по строке открывает PDF."
echo "3) Если всё ок:"
echo "   git add -A"
echo "   git commit -m 'Add invoice history screen: list of issued invoices, tap to open PDF'"
echo "   git push"
echo ""
echo "Бэкап изменённых (не новых) файлов лежит в: $BACKUP_DIR — можно удалить после проверки."
