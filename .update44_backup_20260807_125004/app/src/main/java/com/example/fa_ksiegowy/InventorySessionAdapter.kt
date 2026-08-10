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

/** Список проведённых инвентаризаций — используется на InventoryHistoryActivity. */
class InventorySessionAdapter(
    initialItems: List<InventorySession> = emptyList(),
    private val onItemClick: (InventorySession) -> Unit = {},
    private val onDeleteClick: (InventorySession) -> Unit = {}
) : RecyclerView.Adapter<InventorySessionAdapter.VH>() {
    private var items: List<InventorySession> = initialItems
    private val dateFmt = SimpleDateFormat("dd.MM.yy HH:mm", Locale.getDefault())

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvDate = view.findViewById<TextView>(R.id.tv_session_date)
        val tvNumber = view.findViewById<TextView>(R.id.tv_session_number)
        val tvMeta = view.findViewById<TextView>(R.id.tv_session_meta)
        val tvDiffValue = view.findViewById<TextView>(R.id.tv_session_diff_value)
        val btnDelete = view.findViewById<TextView>(R.id.btn_delete_session)
    }

    fun submitList(newItems: List<InventorySession>) {
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
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_inventory_session, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val s = items[position]
        val context = holder.itemView.context
        holder.tvDate.text = dateFmt.format(Date(s.dateMillis))
        holder.tvNumber.text = context.getString(R.string.inventory_session_number, s.number.toString())
        holder.tvMeta.text = context.getString(R.string.inventory_session_meta, s.totalProducts.toString(), s.changedProducts.toString())
        val sign = if (s.diffValueNet > 0) "+" else ""
        holder.tvDiffValue.text = String.format(Locale.getDefault(), "%s%.2f zł", sign, s.diffValueNet)
        val color = when {
            s.diffValueNet < 0 -> "#FF6B6B"
            s.diffValueNet > 0 -> "#4CD964"
            else -> null
        }
        holder.tvDiffValue.setTextColor(
            if (color != null) android.graphics.Color.parseColor(color)
            else context.getColor(R.color.text_primary)
        )
        holder.itemView.setOnClickListener { onItemClick(s) }
        holder.btnDelete.setOnClickListener { onDeleteClick(s) }
    }

    override fun getItemCount(): Int = items.size
}
