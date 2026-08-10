package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Update: Faktura korygująca — dokument korygujący wcześniej wystawioną fakturę/
 * rachunek (błędna kwota, zwrot części zapłaty, dopłata). Przechowuje deltę
 * (dodatnią lub ujemną różnicę kwoty sprzedaży: correctedAmount - originalAmount)
 * potrzebną do przeliczenia Przychodu — patrz AddInvoiceCorrectionActivity, gdzie
 * ta delta może zostać dodatkowo zapisana jako Entry (korekta przychodu).
 *
 * originalAmount jest kopiowana z oryginalnej faktury w chwili wystawienia korekty
 * (nie odczytywana na bieżąco z Invoice) — żeby historia korekt pozostała spójna
 * nawet gdyby oryginalna faktura została później usunięta.
 */
@Entity(tableName = "invoice_corrections")
data class InvoiceCorrection(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val originalInvoiceId: Long,
    /** Update: numer oryginalnej faktury skopiowany w chwili wystawienia korekty —
     *  z tego samego powodu co originalAmount powyżej: żeby korekta pozostała
     *  czytelna w Historii faktur nawet gdyby oryginalna faktura (Invoice) została
     *  później usunięta. Dla korekt zapisanych PRZED tą aktualizacją (migracja
     *  10->11) wartość domyślna to 0 — InvoiceHistoryActivity w takim wypadku
     *  dogląda numeru z wciąż istniejącej oryginalnej faktury po originalInvoiceId. */
    val originalInvoiceNumber: Int = 0,
    val correctionNumber: Int,
    val issueDateMillis: Long,
    val reason: String,
    val originalAmount: Double,
    val correctedAmount: Double,
    /** correctedAmount - originalAmount — dodatnia (dopłata) lub ujemna (zwrot). */
    val deltaAmount: Double,
    val pdfFilePath: String,
    val pdfFileName: String,
    /** true, jeśli delta została też zapisana jako Entry (korekta przychodu). */
    val appliedToIncome: Boolean = false
)

