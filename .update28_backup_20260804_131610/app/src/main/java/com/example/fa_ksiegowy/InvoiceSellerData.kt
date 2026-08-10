package com.example.fa_ksiegowy

import android.content.Context

/**
 * Dane sprzedawcy (mojej firmy) wyświetlane w nagłówku faktury/rachunku.
 * Przy pierwszym użyciu podpowiadane z danych podatnika (PitPersonalData),
 * ale przechowywane osobno i edytowalne na ekranie wystawiania dokumentu —
 * nie każdy sprzedawca ma NIP (np. działalność nierejestrowana).
 */
data class InvoiceSellerData(
    val name: String = "",
    val nip: String = "",
    val street: String = "",
    val postalCode: String = "",
    val city: String = ""
)

object InvoiceSellerDataStore {
    private const val PREFS = "invoice_seller_data"

    fun load(context: Context): InvoiceSellerData {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hasSaved = p.contains("name")
        if (!hasSaved) {
            // Pierwsze użycie — podpowiadamy z danych podatnika z sekcji PIT.
            val pit = PitDataStore.load(context)
            if (pit.firstName.isNotBlank() || pit.lastName.isNotBlank()) {
                return InvoiceSellerData(
                    name = "${pit.firstName} ${pit.lastName}".trim(),
                    nip = "",
                    street = listOf(pit.street, pit.houseNumber).filter { it.isNotBlank() }.joinToString(" "),
                    postalCode = pit.postalCode,
                    city = pit.city
                )
            }
        }
        return InvoiceSellerData(
            name = p.getString("name", "") ?: "",
            nip = p.getString("nip", "") ?: "",
            street = p.getString("street", "") ?: "",
            postalCode = p.getString("postalCode", "") ?: "",
            city = p.getString("city", "") ?: ""
        )
    }

    fun save(context: Context, data: InvoiceSellerData) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("name", data.name)
            .putString("nip", data.nip)
            .putString("street", data.street)
            .putString("postalCode", data.postalCode)
            .putString("city", data.city)
            .apply()
    }
}
