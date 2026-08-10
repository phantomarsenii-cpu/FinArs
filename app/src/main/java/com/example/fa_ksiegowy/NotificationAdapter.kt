package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class NotificationAdapter(
    private val onDelete: (NotificationLog.Entry) -> Unit
) : RecyclerView.Adapter<NotificationAdapter.VH>() {

    private var items: List<NotificationLog.Entry> = emptyList()
    private val fmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())

    fun submitList(newItems: List<NotificationLog.Entry>) {
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

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val title = view.findViewById<TextView>(R.id.tv_notif_title)
        val text = view.findViewById<TextView>(R.id.tv_notif_text)
        val time = view.findViewById<TextView>(R.id.tv_notif_time)
        val delete = view.findViewById<ImageView>(R.id.iv_notif_delete)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH =
        VH(LayoutInflater.from(parent.context).inflate(R.layout.item_notification, parent, false))

    override fun onBindViewHolder(holder: VH, position: Int) {
        val e = items[position]
        holder.title.text = e.title
        holder.text.text = e.text
        holder.time.text = fmt.format(Date(e.timeMillis))
        holder.delete.setOnClickListener { onDelete(e) }
    }

    override fun getItemCount(): Int = items.size
}
