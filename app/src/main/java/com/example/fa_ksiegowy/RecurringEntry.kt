package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Szablon transakcji cyklicznej (np. czynsz, abonament, stały zlecenie) —
 * co miesiąc RecurringEntryWorker tworzy z niego zwykły wpis w tabeli "entries"
 * i przesuwa nextRunMillis o kolejny miesiąc. dayOfMonth ograniczony do 1..28,
 * żeby uniknąć problemów z miesiącami krótszymi niż 29/30/31 dni.
 */
@Entity(tableName = "recurring_entries")
data class RecurringEntry(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val amount: Double,
    val isIncome: Boolean,
    val comment: String?,
    val dayOfMonth: Int,
    val nextRunMillis: Long,
    val active: Boolean = true
)
