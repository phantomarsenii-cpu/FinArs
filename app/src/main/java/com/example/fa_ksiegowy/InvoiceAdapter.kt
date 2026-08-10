package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Список выставленных счетов/фактур — используется на экране InvoiceHistoryActivity.
 *
 * Update: список теперь смешанный (см. [InvoiceHistoryItem]) — обычные фактуры
 * И korekty (faktury korygujące) в одной хронологической ленте, так как korekta
 * это тоже официально выставленный документ и должна быть видна в истории, а не
 * только с экрана оригинальной фактуры.
 */
class InvoiceAdapter(
    private val onItemClick: (Invoice) -> Unit = {},
    private val onCorrectionClick: (InvoiceCorrection) -> Unit = {},
    private val onDeleteClick: (Invoice) -> Unit = {},
    private val onDeleteCorrectionClick: (InvoiceCorrection) -> Unit = {},
    private val onMarkPaidClick: (Invoice) -> Unit = {},
    private val onKorektaClick: (Invoice) -> Unit = {}
) : RecyclerView.Adapter<InvoiceAdapter.VH>() {
    private var items: List<InvoiceHistoryItem> = emptyList()
    private val dateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvDate = view.findViewById<TextView>(R.id.tv_invoice_date)
        val tvBuyer = view.findViewById<TextView>(R.id.tv_invoice_buyer)
        val tvMeta = view.findViewById<TextView>(R.id.tv_invoice_meta)
        val tvAmount = view.findViewById<TextView>(R.id.tv_invoice_amount)
        val btnDelete = view.findViewById<TextView>(R.id.btn_delete_invoice)
        val btnMarkPaid = view.findViewById<TextView>(R.id.btn_mark_paid)
        val btnKorekta = view.findViewById<TextView>(R.id.btn_korekta)
    }

    /**
     * Заменяет список счетов/корректировок с расчётом разницы через DiffUtil —
     * избегаем полной перерисовки при вводе в поиске или смене фильтра дат, что
     * важно для больших списков фактур. Сравнение по [InvoiceHistoryItem.stableKey],
     * который различает фактуры и корректировки даже при совпадающих числовых id.
     */
    fun submitList(newItems: List<InvoiceHistoryItem>) {
        val old = items
        val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
            override fun getOldListSize() = old.size
            override fun getNewListSize() = newItems.size
            override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int) =
                old[oldItemPosition].stableKey == newItems[newItemPosition].stableKey
            override fun areContentsTheSame(oldItemPosition: Int, newItemPosition: Int) =
                old[oldItemPosition] == newItems[newItemPosition]
        })
        items = newItems
        diff.dispatchUpdatesTo(this)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_invoice, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        when (val item = items[position]) {
            is InvoiceHistoryItem.InvoiceRow -> bindInvoice(holder, item.invoice)
            is InvoiceHistoryItem.CorrectionRow -> bindCorrection(holder, item)
        }
    }

    private fun bindInvoice(holder: VH, inv: Invoice) {
        val context = holder.itemView.context
        holder.tvDate.text = dateFmt.format(Date(inv.issueDateMillis))
        holder.tvBuyer.text = inv.buyerName
        val statusLabel = if (inv.isOverdue) context.getString(R.string.invoice_status_overdue)
            else context.getString(inv.status.labelResId)
        holder.tvMeta.text = "№${inv.invoiceNumber} · " + context.getString(inv.paymentMethod.labelResId) +
            " · " + statusLabel
        holder.tvAmount.text = String.format(Locale.getDefault(), "%.2f", inv.amount)
        val amountColor = when {
            inv.isOverdue -> "#FF6B6B"
            inv.status == InvoiceStatus.PENDING -> "#FFB74D"
            else -> null
        }
        holder.tvAmount.setTextColor(
            if (amountColor != null) android.graphics.Color.parseColor(amountColor)
            else context.getColor(R.color.text_primary)
        )
        holder.btnMarkPaid.visibility = if (inv.status == InvoiceStatus.PENDING) View.VISIBLE else View.GONE
        holder.btnKorekta.visibility = View.VISIBLE
        holder.itemView.setOnClickListener { onItemClick(inv) }
        holder.btnDelete.setOnClickListener { onDeleteClick(inv) }
        holder.btnMarkPaid.setOnClickListener { onMarkPaidClick(inv) }
        holder.btnKorekta.setOnClickListener { onKorektaClick(inv) }
    }

    /**
     * Строка korekty: явно помечена значком "↺" перед номером, сумма показывает
     * ТОЛЬКО дельту (разницу) со знаком и цветом (зелёный — доплата, красный —
     * возврат/уменьшение) — так же, как в самом PDF корректировки. Кнопка "Wystaw
     * korektę" скрыта (korekta к korekcie в текущей модели данных не поддерживается —
     * выставляйте новую корректировку от оригинальной фактуры), кнопка "✓ paid"
     * скрыта (у корректировки нет статуса оплаты), кнопка удаления работает как
     * обычно (удаляет запись и PDF-файл этой корректировки).
     */
    private fun bindCorrection(holder: VH, item: InvoiceHistoryItem.CorrectionRow) {
        val context = holder.itemView.context
        val correction = item.correction
        holder.tvDate.text = dateFmt.format(Date(correction.issueDateMillis))
        holder.tvBuyer.text = "↺ " + if (item.originalInvoiceNumber != null) {
            context.getString(R.string.correction_history_row_title, correction.correctionNumber, item.originalInvoiceNumber)
        } else {
            context.getString(R.string.correction_history_row_title_solo, correction.correctionNumber)
        }
        holder.tvMeta.text = correction.reason
        val delta = correction.deltaAmount
        val sign = if (delta >= 0) "+" else ""
        holder.tvAmount.text = sign + String.format(Locale.getDefault(), "%.2f", delta)
        holder.tvAmount.setTextColor(
            android.graphics.Color.parseColor(if (delta >= 0) "#4CD964" else "#FF6B6B")
        )
        holder.btnMarkPaid.visibility = View.GONE
        holder.btnKorekta.visibility = View.GONE
        holder.itemView.setOnClickListener { onCorrectionClick(correction) }
        holder.btnDelete.setOnClickListener { onDeleteCorrectionClick(correction) }
    }

    override fun getItemCount(): Int = items.size
}
