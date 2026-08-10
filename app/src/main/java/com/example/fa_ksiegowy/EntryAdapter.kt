package com.example.fa_ksiegowy
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class EntryAdapter(
    initialItems: List<Entry> = emptyList(),
    private val onItemClick: (Entry) -> Unit = {}
) : RecyclerView.Adapter<EntryAdapter.VH>() {
    private var items: List<Entry> = initialItems
    private val dateFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvDate = view.findViewById<TextView>(R.id.tv_date)
        val tvAmount = view.findViewById<TextView>(R.id.tv_amount)
        val tvComment = view.findViewById<TextView>(R.id.tv_comment)
        val ivIcon = view.findViewById<ImageView>(R.id.iv_icon)
        val iconBadge = view.findViewById<FrameLayout>(R.id.icon_badge)
    }

    /**
     * Заменяет список записей с расчётом разницы через DiffUtil — это избегает
     * полной перерисовки RecyclerView при каждом изменении поискового запроса
     * или фильтра и остаётся эффективным даже на больших списках операций.
     */
    fun submitList(newItems: List<Entry>) {
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
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_entry, parent, false)
        return VH(v)
    }
    override fun onBindViewHolder(holder: VH, position: Int) {
        val e = items[position]
        val context = holder.itemView.context
        val sign = if (e.isIncome) "+" else "-"
        holder.tvDate.text = dateFmt.format(Date(e.dateMillis))
        holder.tvAmount.text = "$sign ${String.format(Locale.getDefault(), "%.2f", e.amount)} zł"
        holder.tvAmount.setTextColor(
            ContextCompat.getColor(context, if (e.isIncome) R.color.income_green else R.color.expense_red)
        )

        // Tytul wiersza = kategoria (jesli rozpoznana z prefiksu komentarza), w
        // przeciwnym razie caly komentarz, a jesli pusty — ogolna etykieta wg typu.
        val (category, rest) = TransactionCategory.splitComment(context, e.comment, e.isIncome)
        holder.tvComment.text = when {
            category != null -> context.getString(category.labelRes)
            !e.comment.isNullOrBlank() -> e.comment
            else -> context.getString(if (e.isIncome) R.string.tx_income else R.string.tx_expense)
        }

        val iconDef = TransactionCategory.iconFor(context, e.comment, e.isIncome)
        holder.ivIcon.setImageResource(iconDef.icon)
        holder.iconBadge.setBackgroundResource(iconDef.badgeBg)

        // Тап по записи — открыть её на редактирование/удаление (см. AddEntryActivity).
        holder.itemView.setOnClickListener { onItemClick(e) }
    }
    override fun getItemCount(): Int = items.size
}
