package com.example.fa_ksiegowy

import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView

class OnboardingPagerAdapter(private val pages: List<OnboardingPage>) :
    RecyclerView.Adapter<OnboardingPagerAdapter.PageViewHolder>() {

    class PageViewHolder(itemView: android.view.View) : RecyclerView.ViewHolder(itemView) {
        val iconCircle: android.view.View = itemView.findViewById(R.id.onboarding_icon_circle)
        val icon: ImageView = itemView.findViewById(R.id.onboarding_icon)
        val title: TextView = itemView.findViewById(R.id.onboarding_title)
        val description: TextView = itemView.findViewById(R.id.onboarding_description)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PageViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_onboarding_page, parent, false)
        return PageViewHolder(view)
    }

    override fun onBindViewHolder(holder: PageViewHolder, position: Int) {
        val page = pages[position]
        val context = holder.itemView.context
        holder.iconCircle.backgroundTintList =
            ContextCompat.getColorStateList(context, page.iconBgColor)
        holder.icon.setImageResource(page.iconRes)
        holder.title.setText(page.titleRes)
        holder.description.setText(page.descriptionRes)
    }

    override fun getItemCount(): Int = pages.size
}
