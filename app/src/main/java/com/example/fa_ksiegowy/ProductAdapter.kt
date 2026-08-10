package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView

class ProductAdapter(
    private val onClick: (Product) -> Unit,
    private val onLongClick: (Product) -> Boolean
) : RecyclerView.Adapter<ProductAdapter.VH>() {
    private var items: List<Product> = emptyList()

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvName: TextView = view.findViewById(R.id.tv_product_name)
        val tvQty: TextView = view.findViewById(R.id.tv_product_qty)
        val tvBarcode: TextView = view.findViewById(R.id.tv_product_barcode)
    }

    fun submitList(newItems: List<Product>) {
        items = newItems
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_product, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val p = items[position]
        holder.tvName.text = p.name
        holder.tvQty.text = "${formatQty(p.quantity)} ${p.unit}"
        holder.tvQty.setTextColor(
            ContextCompat.getColor(holder.itemView.context, if (p.isLowStock) R.color.expense_red else R.color.text_primary)
        )
        holder.tvBarcode.text = p.barcode ?: ""
        holder.itemView.setOnClickListener { onClick(p) }
        holder.itemView.setOnLongClickListener { onLongClick(p) }
    }

    override fun getItemCount(): Int = items.size

    /** Без лишних ".0" для целых количеств (5 szt., а не 5,0 szt.). */
    private fun formatQty(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
}
