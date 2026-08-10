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
