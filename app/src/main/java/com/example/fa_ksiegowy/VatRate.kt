package com.example.fa_ksiegowy

/**
 * Stawka VAT wybierana przez użytkownika przy wystawianiu faktury, gdy
 * sprzedawca jest już zarejestrowanym podatnikiem VAT (patrz
 * [VatComplianceHelper]). Przechowywana w [Invoice.vatRate] jako storageKey.
 */
enum class VatRate(val storageKey: String, val percent: Double?) {
    RATE_23("23", 23.0),
    RATE_8("8", 8.0),
    RATE_5("5", 5.0),
    RATE_0("0", 0.0),
    ZW("zw", null),
    NP("np", null);

    val labelResId: Int
        get() = when (this) {
            RATE_23 -> R.string.vat_rate_23
            RATE_8 -> R.string.vat_rate_8
            RATE_5 -> R.string.vat_rate_5
            RATE_0 -> R.string.vat_rate_0
            ZW -> R.string.vat_rate_zw
            NP -> R.string.vat_rate_np
        }

    /** Kwota VAT dla podanej wartości netto (0 dla zw./np., gdzie procent nie istnieje). */
    fun vatAmount(netAmount: Double): Double = (percent ?: 0.0) / 100.0 * netAmount

    companion object {
        fun fromStorageKeyOrNull(key: String?): VatRate? = entries.find { it.storageKey == key }
    }
}
