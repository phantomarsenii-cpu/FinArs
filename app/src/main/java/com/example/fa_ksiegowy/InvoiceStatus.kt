package com.example.fa_ksiegowy

/**
 * Status opłacenia faktury/rachunku.
 *
 * OVERDUE nie jest osobną wartością zapisywaną w bazie — to stan obliczany
 * "w locie" (PENDING + dueDateMillis w przeszłości), żeby nie mógł się
 * rozsynchronizować z rzeczywistą datą (patrz Invoice.computedStatus()).
 */
enum class InvoiceStatus {
    PAID,
    PENDING;

    val labelResId: Int
        get() = when (this) {
            PAID -> R.string.invoice_status_paid
            PENDING -> R.string.invoice_status_pending
        }
}
