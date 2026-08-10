package com.example.fa_ksiegowy

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface ProductDao {
    @Insert
    suspend fun insert(product: Product): Long

    @Update
    suspend fun update(product: Product)

    @Delete
    suspend fun delete(product: Product)

    @Query("SELECT * FROM products WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): Product?

    @Query("SELECT * FROM products WHERE barcode = :barcode LIMIT 1")
    suspend fun getByBarcode(barcode: String): Product?

    @Query("SELECT * FROM products ORDER BY name ASC")
    suspend fun getAll(): List<Product>

    @Query("SELECT * FROM products WHERE quantity <= lowStockThreshold")
    suspend fun getLowStock(): List<Product>

    /** Списание при продаже. Остаток не уходит ниже нуля. */
    @Query("UPDATE products SET quantity = MAX(0, quantity - :amount), updatedAtMillis = :now WHERE id = :id")
    suspend fun decrementQuantity(id: Long, amount: Double, now: Long = System.currentTimeMillis())
}
