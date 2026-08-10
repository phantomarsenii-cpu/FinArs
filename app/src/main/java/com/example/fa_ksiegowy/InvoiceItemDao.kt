package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface InvoiceItemDao {
    @Insert
    suspend fun insertAll(items: List<InvoiceItem>)

    @Query("SELECT * FROM invoice_items WHERE invoiceId = :invoiceId")
    suspend fun getForInvoice(invoiceId: Long): List<InvoiceItem>
}
