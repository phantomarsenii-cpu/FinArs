#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 28: UX/дизайн счетов ==="
echo "1) Явная подсветка выбранного способа оплаты (яркая рамка + текст)"
echo "2) PDF счёта на 100%% языке приложения (EN/PL/RU), без смешения языков"
echo "3) Удаление ошибочного счёта из истории (запись + PDF-файл)"
echo "4) Редизайн PDF: таблица позиций, продавец/покупатель рядом, печать ZAPŁACONO, банковский счёт"
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy-main (там, где settings.gradle)"
    exit 1
fi

if [ ! -f "app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt" ]; then
    echo "!!! Не найден InvoiceHistoryActivity.kt — сначала примени update_project-26 и update_project-27"
    exit 1
fi

BACKUP_DIR=".update28_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceSellerData.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/InvoiceFileStorage.kt" \
    "app/src/main/res/layout/item_invoice.xml" \
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
# 1) Файлы, которые полностью перезаписываются
# ============================================================

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT'
package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Buduje PDF dokumentu sprzedaży dla osoby fizycznej (Faktura imienna, gdy
 * sprzedawca jest VAT-owcem, lub Rachunek, gdy nie jest) — z pozycją
 * towaru/usługi w formie tabeli, danymi sprzedawcy/nabywcy obok siebie
 * i pieczątką "ZAPŁACONO". Wszystkie etykiety pochodzą z zasobów string —
 * dokument jest w pełni w języku aktualnie wybranym w aplikacji (kontekst
 * przekazywany przez wywołującego musi mieć już zastosowaną lokalizację,
 * patrz [BaseActivity]/[LocaleHelper] — nie używamy tu applicationContext).
 */
object InvoicePdfGenerator {

    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 48f

    private data class Labels(
        val docKind: String,
        val issueDate: String,
        val saleDate: String,
        val seller: String,
        val buyer: String,
        val nip: String,
        val bankAccount: String,
        val buyerPrivate: String,
        val tableLp: String,
        val tableName: String,
        val tableUnit: String,
        val tableQty: String,
        val tablePrice: String,
        val tableTotal: String,
        val unitPiece: String,
        val sumLabel: String,
        val paidStamp: String,
        val paymentDateLabel: String,
        val paymentStatusLine: String,
        val footer: String
    )

    private fun buildLabels(context: Context, isVatPayer: Boolean, paymentMethod: PaymentMethod): Labels = Labels(
        docKind = context.getString(if (isVatPayer) R.string.invoice_pdf_faktura else R.string.invoice_pdf_rachunek),
        issueDate = context.getString(R.string.invoice_pdf_issue_date),
        saleDate = context.getString(R.string.invoice_pdf_sale_date),
        seller = context.getString(R.string.invoice_pdf_seller),
        buyer = context.getString(R.string.invoice_pdf_buyer),
        nip = context.getString(R.string.invoice_pdf_nip),
        bankAccount = context.getString(R.string.invoice_pdf_bank_account),
        buyerPrivate = context.getString(R.string.invoice_pdf_buyer_private),
        tableLp = context.getString(R.string.invoice_pdf_table_lp),
        tableName = context.getString(R.string.invoice_pdf_table_name),
        tableUnit = context.getString(R.string.invoice_pdf_table_unit),
        tableQty = context.getString(R.string.invoice_pdf_table_qty),
        tablePrice = context.getString(R.string.invoice_pdf_table_price),
        tableTotal = context.getString(R.string.invoice_pdf_table_total),
        unitPiece = context.getString(R.string.invoice_pdf_unit_piece),
        sumLabel = context.getString(R.string.invoice_pdf_sum_label),
        paidStamp = context.getString(R.string.invoice_pdf_paid_stamp),
        paymentDateLabel = context.getString(R.string.invoice_pdf_payment_date),
        paymentStatusLine = context.getString(paymentMethod.paidLabelResId),
        footer = context.getString(R.string.invoice_pdf_footer)
    )

    fun generate(
        context: Context,
        seller: InvoiceSellerData,
        invoiceNumber: Int,
        issueDateMillis: Long,
        paymentDateMillis: Long,
        serviceDateMillis: Long,
        isPhysicalPerson: Boolean,
        buyerName: String,
        buyerNip: String?,
        buyerStreet: String,
        buyerPostalCode: String,
        buyerCity: String,
        serviceName: String,
        amount: Double,
        paymentMethod: PaymentMethod,
        out: OutputStream
    ) {
        val isVatPayer = seller.nip.isNotBlank()
        val l = buildLabels(context, isVatPayer, paymentMethod)

        val document = PdfDocument()
        var pageNumber = 1
        var page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
        var canvas = page.canvas

        val titlePaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 20f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val sectionPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val textPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10.5f; isAntiAlias = true }
        val hintPaint = Paint().apply { color = 0xFF555555.toInt(); textSize = 9f; isAntiAlias = true }
        val tableHeaderPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 9.5f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val tableCellPaint = Paint().apply { color = 0xFF12162E.toInt(); textSize = 10f; isAntiAlias = true }
        val stampPaint = Paint().apply { color = 0xFF1B7F3C.toInt(); textSize = 13f; typeface = Typeface.DEFAULT_BOLD; isAntiAlias = true }
        val linePaint = Paint().apply { color = 0xFFB0B0B0.toInt(); strokeWidth = 0.75f; isAntiAlias = true }
        val headerFillPaint = Paint().apply { color = 0xFFEDEEF5.toInt() }

        var y = MARGIN

        fun newPageIfNeeded(needed: Float) {
            if (y + needed > PAGE_HEIGHT - MARGIN) {
                document.finishPage(page)
                pageNumber++
                page = document.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
                canvas = page.canvas
                y = MARGIN
            }
        }

        fun line(text: String, paint: Paint = textPaint, gap: Float = 15f, x: Float = MARGIN) {
            newPageIfNeeded(gap)
            canvas.drawText(text, x, y, paint)
            y += gap
        }

        fun wrappedLines(text: String, maxCharsPerLine: Int, paint: Paint, gap: Float, x: Float = MARGIN): Float {
            val words = text.split(" ")
            var current = StringBuilder()
            var startY = y
            for (w in words) {
                if (current.length + w.length + 1 > maxCharsPerLine) {
                    newPageIfNeeded(gap)
                    canvas.drawText(current.toString(), x, y, paint)
                    y += gap
                    current = StringBuilder()
                }
                if (current.isNotEmpty()) current.append(" ")
                current.append(w)
            }
            if (current.isNotEmpty()) {
                newPageIfNeeded(gap)
                canvas.drawText(current.toString(), x, y, paint)
                y += gap
            }
            return y - startY
        }

        val money: (Double) -> String = {
            String.format(Locale.US, "%,.2f", it).replace(",", " ").replace(".", ",") + " zł"
        }
        val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

        // --- Nagłówek ---
        line("${l.docKind} nr $invoiceNumber", titlePaint, 26f)
        line("${l.issueDate}: ${dateFmt.format(Date(issueDateMillis))}    ${l.saleDate}: ${dateFmt.format(Date(serviceDateMillis))}", hintPaint, 22f)

        // --- Sprzedawca / Nabywca obok siebie ---
        val colLeftX = MARGIN
        val colRightX = MARGIN + (PAGE_WIDTH - 2 * MARGIN) / 2 + 8f
        val blockTopY = y

        y = blockTopY
        line(l.seller, sectionPaint, 17f, colLeftX)
        if (seller.name.isNotBlank()) line(seller.name, textPaint, 14f, colLeftX)
        val sellerAddress = listOfNotNull(
            seller.street.ifBlank { null },
            listOf(seller.postalCode, seller.city).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (sellerAddress.isNotBlank()) line(sellerAddress, textPaint, 14f, colLeftX)
        if (seller.nip.isNotBlank()) line("${l.nip}: ${seller.nip}", textPaint, 14f, colLeftX)
        if (seller.bankAccount.isNotBlank()) line("${l.bankAccount}: ${seller.bankAccount}", textPaint, 14f, colLeftX)
        val leftBottomY = y

        y = blockTopY
        line(l.buyer, sectionPaint, 17f, colRightX)
        line(buyerName, textPaint, 14f, colRightX)
        val buyerAddress = listOfNotNull(
            buyerStreet.ifBlank { null },
            listOf(buyerPostalCode, buyerCity).filter { it.isNotBlank() }.joinToString(" ").ifBlank { null }
        ).joinToString(", ")
        if (buyerAddress.isNotBlank()) line(buyerAddress, textPaint, 14f, colRightX)
        if (!isPhysicalPerson && !buyerNip.isNullOrBlank()) {
            line("${l.nip}: $buyerNip", textPaint, 14f, colRightX)
        } else {
            wrappedLines(l.buyerPrivate, 46, hintPaint, 12f, colRightX)
        }
        val rightBottomY = y

        y = maxOf(leftBottomY, rightBottomY) + 18f

        // --- Tabela pozycji ---
        val tableLeft = MARGIN
        val tableRight = PAGE_WIDTH - MARGIN
        val tableWidth = tableRight - tableLeft
        val colLp = tableLeft
        val colName = colLp + 28f
        val colUnit = colName + 232f
        val colQty = colUnit + 46f
        val colPrice = colQty + 46f
        val colTotal = colPrice + 72f
        val colStops = floatArrayOf(colLp, colName, colUnit, colQty, colPrice, colTotal, tableRight)

        newPageIfNeeded(70f)
        val headerRowTop = y - 10f
        val headerRowHeight = 20f
        canvas.drawRect(tableLeft, headerRowTop, tableRight, headerRowTop + headerRowHeight, headerFillPaint)
        val headerBaselineY = headerRowTop + headerRowHeight - 6f
        canvas.drawText(l.tableLp, colLp + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableName, colName + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableUnit, colUnit + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableQty, colQty + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tablePrice, colPrice + 4f, headerBaselineY, tableHeaderPaint)
        canvas.drawText(l.tableTotal, colTotal + 4f, headerBaselineY, tableHeaderPaint)

        val dataRowTop = headerRowTop + headerRowHeight
        val dataRowHeight = 22f
        val dataBaselineY = dataRowTop + dataRowHeight - 7f
        canvas.drawText("1", colLp + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(serviceName.take(38), colName + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(l.unitPiece, colUnit + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText("1", colQty + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(money(amount), colPrice + 4f, dataBaselineY, tableCellPaint)
        canvas.drawText(money(amount), colTotal + 4f, dataBaselineY, tableCellPaint)

        val totalRowTop = dataRowTop + dataRowHeight
        val totalRowHeight = 22f
        val totalBaselineY = totalRowTop + totalRowHeight - 7f
        canvas.drawText(l.sumLabel + ":", colPrice - 60f, totalBaselineY, sectionPaint)
        canvas.drawText(money(amount), colTotal + 4f, totalBaselineY, sectionPaint)

        val tableBottom = totalRowTop + totalRowHeight
        // Obramowanie tabeli i linii kolumn/wierszy.
        canvas.drawRect(tableLeft, headerRowTop, tableRight, tableBottom, linePaint.apply { style = Paint.Style.STROKE })
        canvas.drawLine(tableLeft, dataRowTop, tableRight, dataRowTop, linePaint)
        canvas.drawLine(tableLeft, totalRowTop, tableRight, totalRowTop, linePaint)
        for (i in 1 until colStops.size - 1) {
            canvas.drawLine(colStops[i], headerRowTop, colStops[i], totalRowTop, linePaint)
        }

        y = tableBottom + 26f

        // --- Status płatności / pieczątka ---
        newPageIfNeeded(40f)
        line("${l.paymentDateLabel}: ${dateFmt.format(Date(paymentDateMillis))}", textPaint, 16f)
        line(l.paymentStatusLine, textPaint, 20f)
        canvas.drawText("✓ ${l.paidStamp}", tableRight - 130f, y - 4f, stampPaint)
        y += 4f

        // --- Stopka ---
        y += 14f
        newPageIfNeeded(40f)
        wrappedLines(l.footer, 96, hintPaint, 12f)

        document.finishPage(page)
        document.writeTo(out)
        document.close()
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEPDFGENERATOR_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoicePdfGenerator.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceSellerData.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceSellerData.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICESELLERDATA_KT'
package com.example.fa_ksiegowy

import android.content.Context

/**
 * Dane sprzedawcy (mojej firmy) wyświetlane w nagłówku faktury/rachunku.
 * Przy pierwszym użyciu podpowiadane z danych podatnika (PitPersonalData),
 * ale przechowywane osobno i edytowalne na ekranie wystawiania dokumentu —
 * nie każdy sprzedawca ma NIP (np. działalność nierejestrowana).
 */
data class InvoiceSellerData(
    val name: String = "",
    val nip: String = "",
    val street: String = "",
    val postalCode: String = "",
    val city: String = "",
    val bankAccount: String = ""
)

object InvoiceSellerDataStore {
    private const val PREFS = "invoice_seller_data"

    fun load(context: Context): InvoiceSellerData {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hasSaved = p.contains("name")
        if (!hasSaved) {
            // Pierwsze użycie — podpowiadamy z danych podatnika z sekcji PIT.
            val pit = PitDataStore.load(context)
            if (pit.firstName.isNotBlank() || pit.lastName.isNotBlank()) {
                return InvoiceSellerData(
                    name = "${pit.firstName} ${pit.lastName}".trim(),
                    nip = "",
                    street = listOf(pit.street, pit.houseNumber).filter { it.isNotBlank() }.joinToString(" "),
                    postalCode = pit.postalCode,
                    city = pit.city,
                    bankAccount = ""
                )
            }
        }
        return InvoiceSellerData(
            name = p.getString("name", "") ?: "",
            nip = p.getString("nip", "") ?: "",
            street = p.getString("street", "") ?: "",
            postalCode = p.getString("postalCode", "") ?: "",
            city = p.getString("city", "") ?: "",
            bankAccount = p.getString("bankAccount", "") ?: ""
        )
    }

    fun save(context: Context, data: InvoiceSellerData) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("name", data.name)
            .putString("nip", data.nip)
            .putString("street", data.street)
            .putString("postalCode", data.postalCode)
            .putString("city", data.city)
            .putString("bankAccount", data.bankAccount)
            .apply()
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICESELLERDATA_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceSellerData.kt"

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
    private val onItemClick: (Invoice) -> Unit = {},
    private val onDeleteClick: (Invoice) -> Unit = {}
) : RecyclerView.Adapter<InvoiceAdapter.VH>() {
    private val dateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvDate = view.findViewById<TextView>(R.id.tv_invoice_date)
        val tvBuyer = view.findViewById<TextView>(R.id.tv_invoice_buyer)
        val tvMeta = view.findViewById<TextView>(R.id.tv_invoice_meta)
        val tvAmount = view.findViewById<TextView>(R.id.tv_invoice_amount)
        val btnDelete = view.findViewById<TextView>(R.id.btn_delete_invoice)
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
        holder.btnDelete.setOnClickListener { onDeleteClick(inv) }
    }

    override fun getItemCount(): Int = items.size
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEADAPTER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceAdapter.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYACTIVITY_KT'
package com.example.fa_ksiegowy

import android.app.AlertDialog
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
 * Кнопка "✕" на строке удаляет ошибочно выставленный счёт (запись из БД
 * и сохранённый PDF-файл) после подтверждения.
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
                findViewById<RecyclerView>(R.id.rv_invoices).adapter = InvoiceAdapter(
                    items = allInvoices,
                    onItemClick = { invoice -> openInvoicePdf(invoice) },
                    onDeleteClick = { invoice -> confirmDelete(invoice) }
                )
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

    private fun confirmDelete(invoice: Invoice) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_invoice_confirm_title))
            .setMessage(getString(R.string.delete_invoice_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    InvoiceFileStorage.deleteFile(applicationContext, invoice.pdfFilePath)
                    AppDatabase.getInstance(applicationContext).invoiceDao().delete(invoice)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@InvoiceHistoryActivity, getString(R.string.invoice_deleted), Toast.LENGTH_SHORT).show()
                        loadData()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_INVOICEHISTORYACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/InvoiceHistoryActivity.kt"

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

    <TextView
        android:id="@+id/btn_delete_invoice"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="10dp"
        android:padding="6dp"
        android:text="✕"
        android:textColor="#FF6B6B"
        android:textSize="16sp"
        android:textStyle="bold"
        android:clickable="true"
        android:focusable="true"
        android:background="?android:attr/selectableItemBackgroundBorderless"/>

</LinearLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ITEM_INVOICE_XML
echo "OK: app/src/main/res/layout/item_invoice.xml"

mkdir -p "$(dirname "app/src/main/res/drawable/btn_pill_payment_selected.xml")"
cat > app/src/main/res/drawable/btn_pill_payment_selected.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_PAYMENT_SELECTED_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="23dp" />
    <gradient
        android:angle="90"
        android:startColor="@color/accent_blue_light"
        android:centerColor="#2246D6"
        android:endColor="@color/accent_blue_dark" />
    <stroke android:width="2.5dp" android:color="@color/accent_cyan" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_PAYMENT_SELECTED_XML
echo "OK: app/src/main/res/drawable/btn_pill_payment_selected.xml"

mkdir -p "$(dirname "app/src/main/res/drawable/btn_pill_payment_unselected.xml")"
cat > app/src/main/res/drawable/btn_pill_payment_unselected.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_PAYMENT_UNSELECTED_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="23dp" />
    <solid android:color="#12153A" />
    <stroke android:width="1dp" android:color="#2A2E5C" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_PAYMENT_UNSELECTED_XML
echo "OK: app/src/main/res/drawable/btn_pill_payment_unselected.xml"


# ============================================================
# 2) Точечные правки существующих файлов (безопасно перезапускать)
# ============================================================

echo ""
echo "--- Правки существующих файлов ---"

# --- 2.1 InvoiceFileStorage.kt: добавляем deleteFile() ---
python3 - "app/src/main/java/com/example/fa_ksiegowy/InvoiceFileStorage.kt" << 'EOF_PY_STORAGE'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "fun deleteFile" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

anchor = "    val displayFolderPath: String get() = \"Documents/$RELATIVE_FOLDER\"\n}"
if anchor not in content:
    print("!!! Не найден якорь displayFolderPath в %s" % path)
    sys.exit(1)

addition = '''    val displayFolderPath: String get() = "Documents/$RELATIVE_FOLDER"

    /**
     * Usuwa zapisany plik PDF (dziala zarowno dla URI z MediaStore, jak i z
     * FileProvider na starszych Androidach) — uzywane przy kasowaniu bledngo
     * wpisu z historii faktur.
     */
    fun deleteFile(context: Context, uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            context.contentResolver.delete(uri, null, null) > 0
        } catch (e: Exception) {
            false
        }
    }
}'''

content = content.replace(anchor, addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлен deleteFile()" % path)
EOF_PY_STORAGE

# --- 2.2 activity_add_invoice.xml: поле банковского счёта + новые drawable для кнопок оплаты ---
python3 - "app/src/main/res/layout/activity_add_invoice.xml" << 'EOF_PY_LAYOUT'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

changed = False

if "et_seller_bank_account" not in content:
    anchor = '''        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:weightSum="2" android:baselineAligned="false">
            <EditText android:id="@+id/et_seller_postal" style="@style/InvoiceInputHalfStart" android:hint="@string/seller_address_postal" android:inputType="text"/>
            <EditText android:id="@+id/et_seller_city" style="@style/InvoiceInputHalfEnd" android:hint="@string/seller_address_city" android:inputType="text"/>
        </LinearLayout>
'''
    if anchor not in content:
        print("!!! Не найден блок seller_postal/city в activity_add_invoice.xml")
        sys.exit(1)
    addition = anchor + '        <EditText android:id="@+id/et_seller_bank_account" style="@style/InvoiceInput" android:hint="@string/seller_bank_account" android:inputType="text"/>\n'
    content = content.replace(anchor, addition, 1)
    changed = True

if 'android:background="@drawable/btn_pill_primary"\n                android:text="@string/payment_method_cash"' in content:
    content = content.replace(
        'android:background="@drawable/btn_pill_primary"\n                android:text="@string/payment_method_cash"',
        'android:background="@drawable/btn_pill_payment_selected"\n                android:text="@string/payment_method_cash"',
        1
    )
    changed = True
if 'android:background="@drawable/btn_pill_outline"\n                android:text="@string/payment_method_transfer"' in content:
    content = content.replace(
        'android:background="@drawable/btn_pill_outline"\n                android:text="@string/payment_method_transfer"',
        'android:background="@drawable/btn_pill_payment_unselected"\n                android:text="@string/payment_method_transfer"',
        1
    )
    changed = True
if 'android:background="@drawable/btn_pill_outline"\n                android:text="@string/payment_method_blik"' in content:
    content = content.replace(
        'android:background="@drawable/btn_pill_outline"\n                android:text="@string/payment_method_blik"',
        'android:background="@drawable/btn_pill_payment_unselected"\n                android:text="@string/payment_method_blik"',
        1
    )
    changed = True

if not changed:
    print("OK (уже применено): %s" % path)
else:
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: %s -> добавлено поле банковского счёта и новые drawable для кнопок оплаты" % path)
EOF_PY_LAYOUT

# --- 2.3 AddInvoiceActivity.kt: подсветка кнопок, банковский счёт, контекст локализации для PDF ---
python3 - "app/src/main/java/com/example/fa_ksiegowy/AddInvoiceActivity.kt" << 'EOF_PY_ADD'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

changed = False

# 1) Подгрузка банковского счёта в форму
old_load = '''                findViewById<EditText>(R.id.et_seller_city).setText(seller.city)
            }'''
if old_load in content and "et_seller_bank_account).setText" not in content:
    new_load = '''                findViewById<EditText>(R.id.et_seller_city).setText(seller.city)
                findViewById<EditText>(R.id.et_seller_bank_account).setText(seller.bankAccount)
            }'''
    content = content.replace(old_load, new_load, 1)
    changed = True

# 2) Явная подсветка выбранной кнопки способа оплаты (фон + цвет текста)
old_ui = '''    private fun applyPaymentMethodUi() {
        val cash = findViewById<Button>(R.id.btn_payment_cash)
        val transfer = findViewById<Button>(R.id.btn_payment_transfer)
        val blik = findViewById<Button>(R.id.btn_payment_blik)
        cash.setBackgroundResource(if (paymentMethod == PaymentMethod.CASH) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
        transfer.setBackgroundResource(if (paymentMethod == PaymentMethod.TRANSFER) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
        blik.setBackgroundResource(if (paymentMethod == PaymentMethod.BLIK) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
    }'''
if old_ui in content:
    new_ui = '''    private fun applyPaymentMethodUi() {
        val cash = findViewById<Button>(R.id.btn_payment_cash)
        val transfer = findViewById<Button>(R.id.btn_payment_transfer)
        val blik = findViewById<Button>(R.id.btn_payment_blik)
        setPaymentButtonState(cash, paymentMethod == PaymentMethod.CASH)
        setPaymentButtonState(transfer, paymentMethod == PaymentMethod.TRANSFER)
        setPaymentButtonState(blik, paymentMethod == PaymentMethod.BLIK)
    }

    /** Явно выделяем выбранный способ оплаты: яркий фон + жирный белый текст против
     *  приглушённого фона и серого текста у невыбранных — чтобы было сразу видно,
     *  какой способ активен. */
    private fun setPaymentButtonState(button: Button, selected: Boolean) {
        button.setBackgroundResource(if (selected) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        button.setTextColor(resources.getColor(if (selected) R.color.text_primary else R.color.text_secondary, theme))
        button.alpha = if (selected) 1.0f else 0.75f
    }'''
    content = content.replace(old_ui, new_ui, 1)
    changed = True

# 3) Считываем банковский счёт продавца при генерации
old_read = '''        val sellerCity = findViewById<EditText>(R.id.et_seller_city).text.toString().trim()
'''
if old_read in content and "sellerBankAccount" not in content:
    new_read = old_read + '        val sellerBankAccount = findViewById<EditText>(R.id.et_seller_bank_account).text.toString().trim()\n'
    content = content.replace(old_read, new_read, 1)
    changed = True

# 4) Передаём банковский счёт в InvoiceSellerData
old_seller_ctor = "val seller = InvoiceSellerData(sellerName, sellerNip, sellerStreet, sellerPostal, sellerCity)"
if old_seller_ctor in content:
    new_seller_ctor = "val seller = InvoiceSellerData(sellerName, sellerNip, sellerStreet, sellerPostal, sellerCity, sellerBankAccount)"
    content = content.replace(old_seller_ctor, new_seller_ctor, 1)
    changed = True

# 5) PDF должен использовать локализованный контекст активности, а не applicationContext
old_ctx = "                    InvoicePdfGenerator.generate(\n                        context = applicationContext,"
if old_ctx in content:
    new_ctx = "                    InvoicePdfGenerator.generate(\n                        context = this@AddInvoiceActivity,"
    content = content.replace(old_ctx, new_ctx, 1)
    changed = True

if not changed:
    print("OK (уже применено): %s" % path)
else:
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: %s -> подсветка кнопок оплаты, банковский счёт, локализованный контекст PDF" % path)
EOF_PY_ADD

echo "--- Правки применены ---"

# --- 2.4 strings.xml (EN/PL/RU): PDF-метки, банк.счёт, удаление счёта ---
echo "-- English: app/src/main/res/values/strings.xml --"
python3 - "app/src/main/res/values/strings.xml" << 'EOF_PY_STRINGS28_EN'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "invoice_pdf_faktura" in content or "invoice_pdf_rachunek" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''
    <!-- Invoice PDF labels -->
    <string name="invoice_pdf_faktura">INVOICE</string>
    <string name="invoice_pdf_rachunek">RECEIPT</string>
    <string name="invoice_pdf_issue_date">Issue date</string>
    <string name="invoice_pdf_sale_date">Sale date</string>
    <string name="invoice_pdf_seller">Seller</string>
    <string name="invoice_pdf_buyer">Buyer</string>
    <string name="invoice_pdf_nip">Tax ID (NIP)</string>
    <string name="invoice_pdf_bank_account">Bank account</string>
    <string name="invoice_pdf_buyer_private">Private individual (no Tax ID).</string>
    <string name="invoice_pdf_table_lp">No.</string>
    <string name="invoice_pdf_table_name">Item / service</string>
    <string name="invoice_pdf_table_unit">Unit</string>
    <string name="invoice_pdf_table_qty">Qty</string>
    <string name="invoice_pdf_table_price">Price</string>
    <string name="invoice_pdf_table_total">Total</string>
    <string name="invoice_pdf_unit_piece">pc</string>
    <string name="invoice_pdf_sum_label">Total</string>
    <string name="invoice_pdf_paid_stamp">PAID</string>
    <string name="invoice_pdf_payment_date">Payment date</string>
    <string name="invoice_pdf_footer">Document generated in the FinArs app. This is not official accounting or tax advice — if in doubt, consult a tax advisor.</string>
    <string name="seller_bank_account">Bank account (optional)</string>
    <string name="delete_invoice_confirm_title">Delete invoice?</string>
    <string name="delete_invoice_confirm_message">The invoice record and its PDF file will be permanently deleted. This cannot be undone.</string>
    <string name="invoice_deleted">Invoice deleted</string>

</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки" % path)
EOF_PY_STRINGS28_EN

echo "-- Polski: app/src/main/res/values-pl/strings.xml --"
python3 - "app/src/main/res/values-pl/strings.xml" << 'EOF_PY_STRINGS28_PL'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "invoice_pdf_faktura" in content or "invoice_pdf_rachunek" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''
    <!-- Etykiety PDF faktury -->
    <string name="invoice_pdf_faktura">FAKTURA</string>
    <string name="invoice_pdf_rachunek">RACHUNEK</string>
    <string name="invoice_pdf_issue_date">Data wystawienia</string>
    <string name="invoice_pdf_sale_date">Data sprzedaży</string>
    <string name="invoice_pdf_seller">Sprzedawca</string>
    <string name="invoice_pdf_buyer">Nabywca</string>
    <string name="invoice_pdf_nip">NIP</string>
    <string name="invoice_pdf_bank_account">Konto</string>
    <string name="invoice_pdf_buyer_private">Osoba fizyczna nieprowadząca działalności gospodarczej (bez NIP).</string>
    <string name="invoice_pdf_table_lp">Lp</string>
    <string name="invoice_pdf_table_name">Nazwa towaru/usługi</string>
    <string name="invoice_pdf_table_unit">Jedn.</string>
    <string name="invoice_pdf_table_qty">Ilość</string>
    <string name="invoice_pdf_table_price">Cena</string>
    <string name="invoice_pdf_table_total">Razem</string>
    <string name="invoice_pdf_unit_piece">szt</string>
    <string name="invoice_pdf_sum_label">Łącznie</string>
    <string name="invoice_pdf_paid_stamp">ZAPŁACONO</string>
    <string name="invoice_pdf_payment_date">Data zapłaty</string>
    <string name="invoice_pdf_footer">Dokument wygenerowany w aplikacji FinArs. Nie stanowi oficjalnej porady księgowej ani podatkowej — w razie wątpliwości skonsultuj się z doradcą podatkowym.</string>
    <string name="seller_bank_account">Numer konta (opcjonalnie)</string>
    <string name="delete_invoice_confirm_title">Usunąć fakturę?</string>
    <string name="delete_invoice_confirm_message">Wpis oraz plik PDF faktury zostaną trwale usunięte. Tej operacji nie można cofnąć.</string>
    <string name="invoice_deleted">Faktura usunięta</string>

</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки" % path)
EOF_PY_STRINGS28_PL

echo "-- Русский: app/src/main/res/values-ru/strings.xml --"
python3 - "app/src/main/res/values-ru/strings.xml" << 'EOF_PY_STRINGS28_RU'
import sys, io
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "invoice_pdf_faktura" in content or "invoice_pdf_rachunek" in content:
    print("OK (уже применено): %s" % path)
    sys.exit(0)

if "</resources>" not in content:
    print("!!! Не найден </resources> в %s" % path)
    sys.exit(1)

addition = '''
    <!-- Метки PDF счёта -->
    <string name="invoice_pdf_faktura">СЧЁТ-ФАКТУРА</string>
    <string name="invoice_pdf_rachunek">СЧЁТ</string>
    <string name="invoice_pdf_issue_date">Дата выставления</string>
    <string name="invoice_pdf_sale_date">Дата продажи</string>
    <string name="invoice_pdf_seller">Продавец</string>
    <string name="invoice_pdf_buyer">Покупатель</string>
    <string name="invoice_pdf_nip">NIP</string>
    <string name="invoice_pdf_bank_account">Счёт</string>
    <string name="invoice_pdf_buyer_private">Физическое лицо без предпринимательской деятельности (без NIP).</string>
    <string name="invoice_pdf_table_lp">№</string>
    <string name="invoice_pdf_table_name">Наименование товара/услуги</string>
    <string name="invoice_pdf_table_unit">Ед.</string>
    <string name="invoice_pdf_table_qty">Кол-во</string>
    <string name="invoice_pdf_table_price">Цена</string>
    <string name="invoice_pdf_table_total">Сумма</string>
    <string name="invoice_pdf_unit_piece">шт</string>
    <string name="invoice_pdf_sum_label">Итого</string>
    <string name="invoice_pdf_paid_stamp">ОПЛАЧЕНО</string>
    <string name="invoice_pdf_payment_date">Дата оплаты</string>
    <string name="invoice_pdf_footer">Документ создан в приложении FinArs. Не является официальной бухгалтерской или налоговой консультацией — в случае сомнений обратитесь к налоговому консультанту.</string>
    <string name="seller_bank_account">Номер счёта (необязательно)</string>
    <string name="delete_invoice_confirm_title">Удалить счёт?</string>
    <string name="delete_invoice_confirm_message">Запись и PDF-файл счёта будут безвозвратно удалены. Это действие нельзя отменить.</string>
    <string name="invoice_deleted">Счёт удалён</string>

</resources>'''

content = content.replace("</resources>", addition, 1)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("OK: %s -> добавлены строки" % path)
EOF_PY_STRINGS28_RU


echo ""
echo "=== Готово. Дальше вручную: ==="
echo "1) Пересобери APK:  ./gradlew assembleDebug"
echo "2) Проверь:"
echo "   - на экране выставления счёта при выборе способа оплаты кнопка ярко подсвечивается"
echo "   - сгенерируй счёт в разных языках приложения (EN/PL/RU) — весь текст на одном языке"
echo "   - новое поле \"Numer konta (opcjonalnie)\" у продавца — необязательное"
echo "   - в истории счетов кнопка ✕ удаляет счёт (запись + PDF) после подтверждения"
echo "3) Если всё ок:"
echo "   git add -A"
echo "   git commit -m 'Invoice UX: payment method highlight, full PDF localization, table design, delete from history'"
echo "   git push"
echo ""
echo "Бэкап изменённых (не новых) файлов лежит в: $BACKUP_DIR — можно удалить после проверки."
