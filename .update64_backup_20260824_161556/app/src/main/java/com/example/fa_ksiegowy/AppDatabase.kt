package com.example.fa_ksiegowy

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [Entry::class, Invoice::class, RecurringEntry::class, Product::class, InvoiceItem::class, InventoryRecord::class, InventorySession::class, InvoiceCorrection::class],
    version = 12,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun entryDao(): EntryDao

    abstract fun invoiceDao(): InvoiceDao

    abstract fun invoiceCorrectionDao(): InvoiceCorrectionDao

    abstract fun recurringEntryDao(): RecurringEntryDao

    abstract fun productDao(): ProductDao

    abstract fun invoiceItemDao(): InvoiceItemDao

    abstract fun inventoryRecordDao(): InventoryRecordDao

    abstract fun inventorySessionDao(): InventorySessionDao

    companion object {
        /** v3 -> v4: добавлены таблицы склада и позиций фактур. Обычная миграция
         *  (не destructive), чтобы у существующих пользователей не пропали данные. */
        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `products` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `barcode` TEXT, `name` TEXT NOT NULL, `quantity` REAL NOT NULL, `unit` TEXT NOT NULL, `lowStockThreshold` REAL NOT NULL, `priceNet` REAL NOT NULL, `updatedAtMillis` INTEGER NOT NULL)"
                )
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `invoice_items` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `invoiceId` INTEGER NOT NULL, `productId` INTEGER, `name` TEXT NOT NULL, `quantity` REAL NOT NULL, `unitPrice` REAL NOT NULL)"
                )
            }
        }

        /** v4 -> v5: добавлена таблица истории инвентаризации склада. Обычная
         *  миграция (не destructive), чтобы у существующих пользователей не
         *  пропали товары и остальные данные. */
        private val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `inventory_records` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `productId` INTEGER NOT NULL, `productName` TEXT NOT NULL, `unit` TEXT NOT NULL, `quantityBefore` REAL NOT NULL, `quantityCounted` REAL NOT NULL, `dateMillis` INTEGER NOT NULL)"
                )
            }
        }

        /** v5 -> v6: инвентаризация теперь группируется в "сессии" (inventory_sessions,
         *  одна на каждый проведённый пересчёт склада) с сформированным PDF-отчётом;
         *  у записей расхождений (inventory_records) появляется привязка к сессии
         *  (sessionId) и снимок себестоимости товара на момент инвентаризации
         *  (priceNetAtInventory) — для расчёта денежной разницы. Обычная миграция,
         *  без потери уже накопленных данных склада/истории. */
        private val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `inventory_sessions` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `number` INTEGER NOT NULL, `dateMillis` INTEGER NOT NULL, `pdfFilePath` TEXT NOT NULL, `totalProducts` INTEGER NOT NULL, `changedProducts` INTEGER NOT NULL, `diffValueNet` REAL NOT NULL)"
                )
                database.execSQL("ALTER TABLE inventory_records ADD COLUMN sessionId INTEGER NOT NULL DEFAULT 0")
                database.execSQL("ALTER TABLE inventory_records ADD COLUMN priceNetAtInventory REAL NOT NULL DEFAULT 0.0")
            }
        }

        /** v6 -> v7: у товара появляются цена продажи (priceSell) и наценка в % (marginPercent),
         *  цена продажи может задаваться либо вручную, либо через процент наценки от цены
         *  закупки — оба поля синхронизируются на экране редактирования товара. Для уже
         *  существующих товаров priceSell по умолчанию берётся равной текущей priceNet
         *  (закупка = продажа, наценка 0%), чтобы позиции фактур со склада не остались с
         *  нулевой ценой сразу после обновления. У записей инвентаризации (inventory_records)
         *  и сессий (inventory_sessions) появляется снимок цены продажи на момент проверки,
         *  чтобы в таблице расхождений показывать не только разницу по себестоимости, но и
         *  упущенную/лишнюю выручку по цене продажи. */
        private val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE products ADD COLUMN priceSell REAL NOT NULL DEFAULT 0.0")
                database.execSQL("ALTER TABLE products ADD COLUMN marginPercent REAL NOT NULL DEFAULT 0.0")
                database.execSQL("UPDATE products SET priceSell = priceNet")
                database.execSQL("ALTER TABLE inventory_records ADD COLUMN priceSellAtInventory REAL NOT NULL DEFAULT 0.0")
                database.execSQL("ALTER TABLE inventory_sessions ADD COLUMN diffValueSell REAL NOT NULL DEFAULT 0.0")
            }
        }

        /** v7 -> v8: ryczałt теперь считается не одной глобальной ставкой из настроек,
         *  а по КАЖДОЙ операции отдельно (см. RyczaltCategory) — один человек может
         *  одновременно продавать товары (3%/5,5%) и оказывать услуги (8,5%/12%/14%/17%).
         *  У доходов (entries) и позиций фактур (invoice_items) появляется необязательная
         *  привязка к категории; уже существующие записи остаются с NULL и по-прежнему
         *  считаются по старой единой ставке из настроек (см. TaxHelper.calcRyczaltByCategory) —
         *  обычная миграция, без потери накопленной истории. */
        private val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE entries ADD COLUMN ryczaltCategory TEXT")
                database.execSQL("ALTER TABLE invoice_items ADD COLUMN ryczaltCategory TEXT")
            }
        }

        /** v8 -> v9: po przekroczeniu limitu zwolnienia z VAT (240 000 zł) i potwierdzeniu
         *  rejestracji w Ustawieniach użytkownik wybiera stawkę VAT na każdej fakturze
         *  (vatRate) — zapisywana jako storageKey [VatRate]. Po potwierdzeniu posiadania
         *  kasy fiskalnej (limit 20 000 zł gotówki od osób fizycznych) faktura może być
         *  dodatkowo oznaczona jako wystawiona "do paragonu" (isReceipt). Obie kolumny są
         *  opcjonalne — dla wszystkich wcześniejszych faktur pozostają NULL/false, bez
         *  utraty już zapisanych danych. */
        private val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE invoices ADD COLUMN vatRate TEXT")
                database.execSQL("ALTER TABLE invoices ADD COLUMN isReceipt INTEGER NOT NULL DEFAULT 0")
            }
        }

        /** v9 -> v10: moduł Korekta (Faktura korygująca) — nowa tabela przechowująca
         *  wystawione korekty wcześniejszych faktur/rachunków wraz z deltą kwoty
         *  sprzedaży (patrz InvoiceCorrection). Obyczajna migracja, bez utraty
         *  już zapisanych danych. */
        private val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "CREATE TABLE IF NOT EXISTS `invoice_corrections` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `originalInvoiceId` INTEGER NOT NULL, `correctionNumber` INTEGER NOT NULL, `issueDateMillis` INTEGER NOT NULL, `reason` TEXT NOT NULL, `originalAmount` REAL NOT NULL, `correctedAmount` REAL NOT NULL, `deltaAmount` REAL NOT NULL, `pdfFilePath` TEXT NOT NULL, `pdfFileName` TEXT NOT NULL, `appliedToIncome` INTEGER NOT NULL DEFAULT 0)"
                )
            }
        }

        /** v10 -> v11: Historia faktur теперь показывает и обычные фактуры, и
         *  korekty (faktury korygujące) в ЕДИНОМ списке (см. InvoiceHistoryItem,
         *  InvoiceHistoryActivity) — раньше korekty были видны только через
         *  экран original фактуры и вообще не сохранялись в Historii. Чтобы строка
         *  korekty в истории оставалась читаемой даже если оригинальная Invoice
         *  будет позже удалена, копируем номер оригинальной фактуры прямо в
         *  InvoiceCorrection (тот же приём, что уже применён к originalAmount). */
        private val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE invoice_corrections ADD COLUMN originalInvoiceNumber INTEGER NOT NULL DEFAULT 0")
                database.execSQL(
                    "UPDATE invoice_corrections SET originalInvoiceNumber = (" +
                        "SELECT invoiceNumber FROM invoices WHERE invoices.id = invoice_corrections.originalInvoiceId" +
                        ") WHERE EXISTS (SELECT 1 FROM invoices WHERE invoices.id = invoice_corrections.originalInvoiceId)"
                )
            }
        }

        /** v11 -> v12: każda pozycja faktury (invoice_items) ma teraz WŁASNĄ stawkę VAT
         *  (vatRate, storageKey [VatRate]) zamiast jednej wspólnej stawki na całą fakturę
         *  (Invoice.vatRate, pozostawione bez zmian jako "podgląd" — patrz AddInvoiceActivity) —
         *  różne towary/usługi na jednej fakturze mogą być opodatkowane różnymi stawkami.
         *  Obyczajna migracja, bez utraty już zapisanych danych — dla wszystkich wcześniej
         *  zapisanych pozycji kolumna pozostaje NULL. */
        private val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE invoice_items ADD COLUMN vatRate TEXT")
            }
        }

        @Volatile private var INSTANCE: AppDatabase? = null
        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "fa_ksiegowy.db"
                ).addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11, MIGRATION_11_12).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }
    }
}

