package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Lista transakcji pogrupowana wg miesiaca (naglowek "Sierpien 2026" itd.), dokladnie
 * jak w makiecie ekranu "Transakcje". W przeciwienstwie do EntryAdapter (uzywanego na
 * ekranie glownym dla krotkiej listy "Ostatnie transakcje" bez naglowkow), ten adapter
 * buduje plaska liste [Row] mieszajaca naglowki miesiecy i wiersze operacji.
 */
class HistoryAdapter(
    private val onItemClick: (Entry) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private sealed class Row {
        data class Header(val label: String) : Row()
        data class Item(val entry: Entry) : Row()
    }

    private var rows: List<Row> = emptyList()
    private val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
    private val monthFmt = SimpleDateFormat("LLLL yyyy", Locale.getDefault())

    /** Wpisy powinny juz przyjsc posortowane malejaco po dacie (najnowsze pierwsze). */
    fun submitEntries(entries: List<Entry>) {
        val newRows = mutableListOf<Row>()
        var lastMonthKey = ""
        val cal = Calendar.getInstance()
        for (e in entries) {
            cal.timeInMillis = e.dateMillis
            val key = "${cal.get(Calendar.YEAR)}-${cal.get(Calendar.MONTH)}"
            if (key != lastMonthKey) {
                val label = monthFmt.format(Date(e.dateMillis)).replaceFirstChar { it.uppercase() }
                newRows.add(Row.Header(label))
                lastMonthKey = key
            }
            newRows.add(Row.Item(e))
        }
        rows = newRows
        notifyDataSetChanged()
    }

    override fun getItemViewType(position: Int): Int = when (rows[position]) {
        is Row.Header -> TYPE_HEADER
        is Row.Item -> TYPE_ITEM
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return if (viewType == TYPE_HEADER) {
            val tv = TextView(parent.context).apply {
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
                textSize = 13f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                val pad = (14 * resources.displayMetrics.density).toInt()
                setPadding(2, pad, 2, (8 * resources.displayMetrics.density).toInt())
            }
            HeaderVH(tv)
        } else {
            ItemVH(inflater.inflate(R.layout.item_entry, parent, false))
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = rows[position]) {
            is Row.Header -> (holder as HeaderVH).tv.text = row.label
            is Row.Item -> bindItem(holder as ItemVH, row.entry)
        }
    }

    private fun bindItem(holder: ItemVH, e: Entry) {
        val context = holder.itemView.context
        val sign = if (e.isIncome) "+" else "-"
        holder.tvDate.text = dateFmt.format(Date(e.dateMillis))
        holder.tvAmount.text = "$sign ${String.format(Locale.getDefault(), "%.2f", e.amount)} zł"
        holder.tvAmount.setTextColor(
            ContextCompat.getColor(context, if (e.isIncome) R.color.income_green else R.color.expense_red)
        )

        val (category, _) = TransactionCategory.splitComment(context, e.comment, e.isIncome)
        holder.tvComment.text = when {
            category != null -> context.getString(category.labelRes)
            !e.comment.isNullOrBlank() -> e.comment
            else -> context.getString(if (e.isIncome) R.string.tx_income else R.string.tx_expense)
        }

        val iconDef = TransactionCategory.iconFor(context, e.comment, e.isIncome)
        holder.ivIcon.setImageResource(iconDef.icon)
        holder.iconBadge.setBackgroundResource(iconDef.badgeBg)

        holder.itemView.setOnClickListener { onItemClick(e) }
    }

    override fun getItemCount(): Int = rows.size

    class HeaderVH(val tv: TextView) : RecyclerView.ViewHolder(tv)
    class ItemVH(view: View) : RecyclerView.ViewHolder(view) {
        val tvDate = view.findViewById<TextView>(R.id.tv_date)
        val tvAmount = view.findViewById<TextView>(R.id.tv_amount)
        val tvComment = view.findViewById<TextView>(R.id.tv_comment)
        val ivIcon = view.findViewById<ImageView>(R.id.iv_icon)
        val iconBadge = view.findViewById<FrameLayout>(R.id.icon_badge)
    }

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_ITEM = 1
    }
}
