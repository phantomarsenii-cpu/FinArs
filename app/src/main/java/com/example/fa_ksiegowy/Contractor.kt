package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Zapisany kontrahent (nabywca) — dane wypełniane wcześniej w sekcji "Nabywca"
 * na ekranie AddInvoiceActivity, zapisane na żądanie sprzedawcy (przycisk
 * "Zapisz nabywcę"), żeby przy kolejnej fakturze można je było wybrać z listy
 * (SelectContractorActivity) zamiast wpisywać ręcznie od nowa.
 */
@Entity(tableName = "contractors")
data class Contractor(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val isPhysicalPerson: Boolean,
    val name: String,
    val nip: String?,
    val street: String,
    val postalCode: String,
    val city: String,
    val updatedAtMillis: Long = System.currentTimeMillis()
)
