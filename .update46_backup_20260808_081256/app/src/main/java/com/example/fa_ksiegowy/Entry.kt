package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "entries")
data class Entry(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val amount: Double,
    val isIncome: Boolean,
    val comment: String?,
    val dateMillis: Long,
    val receiptPath: String?
)
