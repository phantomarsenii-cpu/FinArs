package com.example.fa_ksiegowy

/**
 * Update: jeden wiersz na ekranie InvoiceHistoryActivity — albo zwykła wystawiona
 * faktura/rachunek, albo faktura korygująca (korekta) do wcześniej wystawionego
 * dokumentu. Korekta jest formalnie też fakturą, więc musi być widoczna w Historii
 * faktur na równi ze zwykłymi fakturami — wcześniej korekty nie trafiały do tej
 * listy wcale i były osiągalne tylko z poziomu oryginalnej faktury.
 *
 * Stabilny klucz (patrz [stableKey]) rozróżnia oba typy nawet gdy invoice.id i
 * correction.id przypadkiem się pokrywają (osobne tabele, osobne sekwencje ID).
 */
sealed class InvoiceHistoryItem {
    abstract val issueDateMillis: Long
    abstract val stableKey: String

    data class InvoiceRow(val invoice: Invoice) : InvoiceHistoryItem() {
        override val issueDateMillis get() = invoice.issueDateMillis
        override val stableKey get() = "inv_${invoice.id}"
    }

    /**
     * @param originalInvoiceNumber numer oryginalnej faktury — brany z
     *   [InvoiceCorrection.originalInvoiceNumber], gdy zapisany (>0), a dla starszych
     *   rekordów sprzed migracji 10->11 (0) — z aktualnego numeru wciąż istniejącej
     *   oryginalnej faktury (patrz [InvoiceHistoryActivity.loadData]); jeśli oryginał
     *   też został usunięty, wynikiem jest null i UI pokazuje samą korektę bez numeru.
     */
    data class CorrectionRow(val correction: InvoiceCorrection, val originalInvoiceNumber: Int?) : InvoiceHistoryItem() {
        override val issueDateMillis get() = correction.issueDateMillis
        override val stableKey get() = "cor_${correction.id}"
    }
}
