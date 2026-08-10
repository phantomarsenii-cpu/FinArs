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

/** Список выставленных счетов/фактур — используется на экране InvoiceHistoryActivity. */
class InvoiceAdapter(
    initialItems: List<Invoice> = emptyList(),
    private val onItemClick: (Invoice) -> Unit = {},
    private val onDeleteClick: (Invoice) -> Unit = {},
    private val onMarkPaidClick: (Invoice) -> Unit = {},
    private val onKorektaClick: (Invoice) -> Unit = {}
) : RecyclerView.Adapter<InvoiceAdapter.VH>() {
    private var items: List<Invoice> = initialItems
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
     * Заменяет список счетов с расчётом разницы через DiffUtil — избегаем полной
     * перерисовки при вводе в поиске или смене фильтра дат, что важно для
     * больших списков фактур.
     */
    fun submitList(newItems: List<Invoice>) {
        val old = items
        val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
            override fun getOldListSize() = old.size
            override fun getNewListSize() = newItems.size
            override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int) =
                old[oldItemPosition].id == newItems[newItemPosition].id
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
        val inv = items[position]
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
        holder.itemView.setOnClickListener { onItemClick(inv) }
        holder.btnDelete.setOnClickListener { onDeleteClick(inv) }
        holder.btnMarkPaid.setOnClickListener { onMarkPaidClick(inv) }
        holder.btnKorekta.setOnClickListener { onKorektaClick(inv) }
    }

    override fun getItemCount(): Int = items.size
}


