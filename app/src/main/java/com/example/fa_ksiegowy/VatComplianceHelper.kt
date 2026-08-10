package com.example.fa_ksiegowy

import android.content.Context
import android.content.SharedPreferences

/**
 * Kontrola dwóch jednorazowych potwierdzeń, które użytkownik musi zaznaczyć
 * w Ustawieniach po przekroczeniu odpowiednich limitów, zanim będzie mógł
 * dalej wystawiać faktury:
 *
 *  1) VAT_REGISTERED — po przekroczeniu rocznego limitu zwolnienia
 *     podmiotowego z VAT (240 000 zł, zob. [LimitsHelper.VAT_EXEMPT_LIMIT])
 *     użytkownik musi złożyć VAT-R i potwierdzić rejestrację, zanim
 *     wystawi kolejną fakturę — od tego momentu każda faktura wymaga
 *     wyboru stawki VAT (zob. [VatRate]).
 *  2) KASA_FISKALNA — po przekroczeniu rocznego limitu 20 000 zł sprzedaży
 *     gotówkowej dla osób fizycznych (zob. [CashLimitHelper]) użytkownik
 *     musi potwierdzić posiadanie kasy fiskalnej.
 *
 * Oba potwierdzenia są ZAPISYWANE RAZ i nie można ich cofnąć z poziomu
 * aplikacji (checkbox w Ustawieniach staje się nieedytowalny po zaznaczeniu) —
 * to świadome zabezpieczenie przed przypadkowym „odznaczeniem" stanu prawnego,
 * który w rzeczywistości już nastąpił.
 */
object VatComplianceHelper {

    private const val KEY_VAT_REGISTERED = "vat_registered_confirmed"
    private const val KEY_KASA_FISKALNA = "kasa_fiskalna_confirmed"
    const val KEY_PUSH_FREQUENCY = "push_notif_per_day"
    const val DEFAULT_PUSH_FREQUENCY = 3

    fun isVatRegisteredConfirmed(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(KEY_VAT_REGISTERED, false)

    /** Zapisuje potwierdzenie rejestracji VAT — jednorazowo, bez możliwości cofnięcia. */
    fun confirmVatRegistered(prefs: SharedPreferences) {
        prefs.edit().putBoolean(KEY_VAT_REGISTERED, true).apply()
    }

    fun isKasaFiskalnaConfirmed(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(KEY_KASA_FISKALNA, false)

    /** Zapisuje potwierdzenie posiadania kasy fiskalnej — jednorazowo, bez możliwości cofnięcia. */
    fun confirmKasaFiskalna(prefs: SharedPreferences) {
        prefs.edit().putBoolean(KEY_KASA_FISKALNA, true).apply()
    }

    fun getPushFrequency(prefs: SharedPreferences): Int =
        prefs.getInt(KEY_PUSH_FREQUENCY, DEFAULT_PUSH_FREQUENCY).coerceIn(1, 50)

    fun setPushFrequency(prefs: SharedPreferences, perDay: Int) {
        prefs.edit().putInt(KEY_PUSH_FREQUENCY, perDay.coerceIn(1, 50)).apply()
    }

    /** Stan zgodności potrzebny na ekranie wystawiania faktury: czy limit VAT/kasy
     *  jest przekroczony i czy dotyczące go potwierdzenie zostało już złożone. */
    data class ComplianceStatus(
        val vatExceeded: Boolean,
        val vatConfirmed: Boolean,
        val cashExceeded: Boolean,
        val kasaConfirmed: Boolean
    ) {
        /** Wystawianie faktur jest zablokowane, dopóki brakującego potwierdzenia nie złożono. */
        val invoicingBlocked: Boolean
            get() = (vatExceeded && !vatConfirmed) || (cashExceeded && !kasaConfirmed)

        /** Czy sprzedawca jest już podatnikiem VAT — wymaga wyboru stawki na każdej fakturze. */
        val requiresVatRateSelection: Boolean get() = vatConfirmed

        /** Czy pokazać opcję „faktura do paragonu" — dostępna dopiero po potwierdzeniu kasy. */
        val allowsReceiptFlag: Boolean get() = kasaConfirmed
    }

    suspend fun computeStatus(context: Context): ComplianceStatus {
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val vatConfirmed = isVatRegisteredConfirmed(prefs)
        val kasaConfirmed = isKasaFiskalnaConfirmed(prefs)
        val limits = LimitsHelper.compute(context)
        val cash = CashLimitHelper.computeCurrentYear(context)
        return ComplianceStatus(
            vatExceeded = limits.vat.exceeded,
            vatConfirmed = vatConfirmed,
            cashExceeded = cash.exceeded,
            kasaConfirmed = kasaConfirmed
        )
    }
}
