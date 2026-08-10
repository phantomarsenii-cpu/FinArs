package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Одна проведённая инвентаризация склада целиком: порядковый номер (для
 * имени файла и заголовка PDF), когда проводилась, путь к сформированному
 * PDF-отчёту и сводные цифры — чтобы список истории строился без повторного
 * чтения PDF или пересчёта по [InventoryRecord].
 */
@Entity(tableName = "inventory_sessions")
data class InventorySession(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val number: Int,
    val dateMillis: Long,
    val pdfFilePath: String,
    val totalProducts: Int,
    val changedProducts: Int,
    val diffValueNet: Double
)
