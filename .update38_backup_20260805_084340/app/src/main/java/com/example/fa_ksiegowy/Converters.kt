package com.example.fa_ksiegowy

import androidx.room.TypeConverter

/** Room nie wspiera enumów natywnie (w wersji 2.5.0) — zapisujemy jako String. */
class Converters {
    @TypeConverter
    fun fromPaymentMethod(value: PaymentMethod): String = value.name

    @TypeConverter
    fun toPaymentMethod(value: String): PaymentMethod =
        PaymentMethod.values().firstOrNull { it.name == value } ?: PaymentMethod.CASH
}
