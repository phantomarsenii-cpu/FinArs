package com.example.fa_ksiegowy

import android.content.Context

/**
 * Lekki system kategorii operacji — NIE jest osobnym polem w bazie (Entry.comment
 * pozostaje jedynym zrodlem tekstu), zeby uniknac migracji Room. Wybrana kategoria
 * jest zapisywana jako czytelny prefiks komentarza ("Paliwo — tankowanie") — patrz
 * AddEntryActivity. Ta klasa dostarcza liste kategorii do wyboru (Dodaj) oraz
 * dopasowuje ikone/kolor dla listy transakcji (Start/Transakcje) na podstawie
 * prefiksu lub, dla starszych wpisow, prostego dopasowania slow kluczowych.
 */
object TransactionCategory {

    data class Def(
        val id: String,
        val labelRes: Int,
        val icon: Int,
        val badgeBg: Int
    )

    fun incomeCategories(context: Context): List<Def> = listOf(
        Def("sale", R.string.category_sale, R.drawable.ic_cat_income, R.drawable.icon_badge_vivid_green),
        Def("invoice", R.string.category_invoice, R.drawable.ic_cat_invoice, R.drawable.icon_badge_vivid_blue),
        Def("other", R.string.category_other, R.drawable.ic_cat_income, R.drawable.icon_badge_vivid_green)
    )

    fun expenseCategories(context: Context): List<Def> = listOf(
        Def("materials", R.string.category_materials, R.drawable.ic_cat_cart, R.drawable.icon_badge_vivid_red),
        Def("fuel", R.string.category_fuel, R.drawable.ic_cat_fuel, R.drawable.icon_badge_vivid_orange),
        Def("transport", R.string.category_transport, R.drawable.ic_cat_truck, R.drawable.icon_badge_vivid_red),
        Def("other", R.string.category_other, R.drawable.ic_cat_expense, R.drawable.icon_badge_vivid_red)
    )

    /** Rozdziela zapisany komentarz na (kategoria|null, reszta_komentarza) — patrz format zapisu w AddEntryActivity. */
    fun splitComment(context: Context, comment: String?, isIncome: Boolean): Pair<Def?, String> {
        if (comment.isNullOrBlank()) return null to ""
        val all = incomeCategories(context) + expenseCategories(context)
        val sepIdx = comment.indexOf(" — ")
        val head = if (sepIdx >= 0) comment.substring(0, sepIdx) else comment
        val rest = if (sepIdx >= 0) comment.substring(sepIdx + 3) else ""
        val match = all.firstOrNull { context.getString(it.labelRes).equals(head.trim(), ignoreCase = true) }
        return if (match != null) match to rest else null to comment
    }

    /** Ikona/kolor dla wiersza listy — najpierw sprobuj rozpoznac zapisana kategorie
     *  (prefiks komentarza), w przeciwnym razie dopasuj po slowach kluczowych (stare
     *  wpisy sprzed wprowadzenia kategorii), a na koncu uzyj domyslnej ikony przychodu/wydatku. */
    fun iconFor(context: Context, comment: String?, isIncome: Boolean): Def {
        val (matched, _) = splitComment(context, comment, isIncome)
        if (matched != null) return matched

        val text = comment?.lowercase().orEmpty()
        val keywordMap = listOf(
            listOf("paliwo", "fuel", "топливо", "benzyna", "diesel") to expenseFind("fuel", context),
            listOf("transport", "усл", "kurier", "dostaw", "delivery") to expenseFind("transport", context),
            listOf("materia", "zakup", "purchase", "закуп", "towar") to expenseFind("materials", context),
            listOf("faktura", "invoice", "счет", "счёт") to incomeFind("invoice", context),
            listOf("sprzedaż", "sprzedaz", "sale", "продаж") to incomeFind("sale", context)
        )
        for ((keywords, def) in keywordMap) {
            if (def != null && keywords.any { text.contains(it) }) return def
        }

        return if (isIncome) incomeCategories(context).first { it.id == "sale" }
        else expenseCategories(context).first { it.id == "other" }
    }

    private fun expenseFind(id: String, context: Context) = expenseCategories(context).firstOrNull { it.id == id }
    private fun incomeFind(id: String, context: Context) = incomeCategories(context).firstOrNull { it.id == id }
}
