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
    val pdfFileName: String,

    /** Status opłacenia — PAID (domyślnie, zgodność wsteczna ze starymi rekordami) lub PENDING. */
    val status: InvoiceStatus = InvoiceStatus.PAID,
    /** Termin płatności — używany tylko gdy status = PENDING (przypomnienia, oznaczenie "zaległa"). */
    val dueDateMillis: Long? = null,

    /** Stawka VAT (storageKey [VatRate]) — wypełniana tylko gdy sprzedawca jest już
     *  zarejestrowanym podatnikiem VAT (zob. [VatComplianceHelper]). null oznacza
     *  fakturę wystawioną przed rejestracją VAT (zwolnienie podmiotowe). */
    val vatRate: String? = null,
    /** true, jeśli ta faktura jest jednocześnie wystawiana "do paragonu" z kasy
     *  fiskalnej (zob. [VatComplianceHelper.confirmKasaFiskalna]) — dotyczy tylko
     *  sprzedaży zarejestrowanej przez kasę fiskalną osobom fizycznym. */
    val isReceipt: Boolean = false
) {
    /** true, jeśli faktura oczekuje na zapłatę i termin już minął. Liczone na bieżąco, nie zapisywane w bazie. */
    val isOverdue: Boolean
        get() = status == InvoiceStatus.PENDING && dueDateMillis != null && dueDateMillis < System.currentTimeMillis()
}
