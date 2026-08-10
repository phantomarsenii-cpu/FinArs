package com.example.fa_ksiegowy

/**
 * Sposób płatności za fakturę/rachunek.
 *
 * Tylko CASH (Gotówka) wlicza się do rocznego limitu 20 000 PLN sprzedaży
 * gotówkowej dla osób fizycznych (art. 111 ust. 1 ustawy o VAT — obowiązek
 * kasy fiskalnej po przekroczeniu limitu). TRANSFER i BLIK jako płatności
 * bezgotówkowe nie są wliczane do tego limitu.
 */
enum class PaymentMethod {
    CASH,
    TRANSFER,
    BLIK;

    val countsTowardCashLimit: Boolean get() = this == CASH

    val labelResId: Int
        get() = when (this) {
            CASH -> R.string.payment_method_cash
            TRANSFER -> R.string.payment_method_transfer
            BLIK -> R.string.payment_method_blik
        }

    /** Fraza dopisywana na dokumencie przy płatności bezgotówkowej, np. "Zapłacono przelewem". */
    val paidLabelResId: Int
        get() = when (this) {
            CASH -> R.string.payment_paid_cash
            TRANSFER -> R.string.payment_paid_transfer
            BLIK -> R.string.payment_paid_blik
        }
}
