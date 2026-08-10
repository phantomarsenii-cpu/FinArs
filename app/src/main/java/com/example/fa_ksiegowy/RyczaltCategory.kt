package com.example.fa_ksiegowy

/**
 * Ставки ryczałtu od przychodów ewidencjonowanych, которые чаще всего встречаются
 * у freelancer'ów/JDG. Один и тот же человек может одновременно продавать товары
 * (3% / 5,5%) и оказывать разные услуги (8,5% / 12% usługi IT / 14% usługi medyczne /
 * 17% wolny zawód) — поэтому ставка выбирается для КАЖДОЙ позиции дохода отдельно
 * (см. AddEntryActivity — доход, AddInvoiceActivity — позиция фактуры), а не одна
 * общая ставка на всё приложение, как было раньше (Ustawienia -> Stawka ryczałtu).
 */
enum class RyczaltCategory(val ratePercent: Double, val labelRes: Int) {
    RATE_3(3.0, R.string.ryczalt_cat_3),
    RATE_5_5(5.5, R.string.ryczalt_cat_5_5),
    RATE_8_5(8.5, R.string.ryczalt_cat_8_5),
    RATE_12(12.0, R.string.ryczalt_cat_12),
    RATE_14(14.0, R.string.ryczalt_cat_14),
    RATE_17(17.0, R.string.ryczalt_cat_17);

    companion object {
        /** Безопасный разбор значения, сохранённого в БД (Entry.ryczaltCategory /
         *  InvoiceItem.ryczaltCategory) — null или неизвестное значение возвращает null,
         *  не бросая исключение (например, если в будущем категория будет переименована). */
        fun fromStorageKeyOrNull(key: String?): RyczaltCategory? =
            if (key.isNullOrBlank()) null else try {
                valueOf(key)
            } catch (e: IllegalArgumentException) {
                null
            }
    }
}
