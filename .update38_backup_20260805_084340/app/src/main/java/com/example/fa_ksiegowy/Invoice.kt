package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Faktura imienna / Rachunek wystawiony klientowi — osobie fizycznej
 * (bez NIP) lub firmie (z NIP). Przechowuje dane nabywcy, kwotę, sposób
 * płatności (potrzebny do kontroli limitu 20 000 PLN gotówki) oraz ścieżkę
 * (URI z MediaStore) do zapisanego pliku PDF.
 */
@Entity(tableName = "invoices")
data class Invoice(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    /** Kolejny numer dokumentu (1, 2, 3…), używany też w nazwie pliku PDF. */
    val invoiceNumber: Int,
    /** Data wystawienia dokumentu (moment utworzenia w aplikacji). */
    val issueDateMillis: Long,
    /** Data faktycznej zapłaty. */
    val paymentDateMillis: Long,
    /** Data wykonania usługi / sprzedaży towaru. */
    val serviceDateMillis: Long,

    val isPhysicalPerson: Boolean,
    val buyerName: String,
    val buyerNip: String?,
    val buyerStreet: String,
    val buyerPostalCode: String,
    val buyerCity: String,

    val serviceName: String,
    val amount: Double,
    val paymentMethod: PaymentMethod,

    /** Content URI (MediaStore) lub ścieżka do zapisanego pliku PDF. */
    val pdfFilePath: String,
    val pdfFileName: String
)
