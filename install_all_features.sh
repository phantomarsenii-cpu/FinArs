#!/bin/bash

# FA_ksiegowy - Complete Setup Script
# Полная установка OCR, Warehouse Management, Barcode Scanner

set -e

PROJECT_ROOT="${1:-.}"
KOTLIN_DIR="$PROJECT_ROOT/app/src/main/java/com/example/fa_ksiegowy"
RES_DIR="$PROJECT_ROOT/app/src/main/res"
LAYOUT_DIR="$RES_DIR/layout"
VALUES_DIR="$RES_DIR/values"
MANIFEST="$PROJECT_ROOT/app/src/main/AndroidManifest.xml"
BUILD_GRADLE="$PROJECT_ROOT/app/build.gradle"

echo "════════════════════════════════════════════════════════════"
echo "Installing: OCR, Warehouse & Barcode Features"
echo "════════════════════════════════════════════════════════════"

# ============= ЗАВИСИМОСТИ =============
echo "[1/15] Adding dependencies..."

if ! grep -q "org.opencv" "$BUILD_GRADLE"; then
    sed -i '/dependencies {/a\    implementation "com.google.mlkit:vision-common:17.3.0"\n    implementation "com.google.mlkit:text-recognition:16.0.0"\n    implementation "org.opencv:opencv-android:4.8.0"\n    implementation "com.journeyapps:zxing-android-embedded:4.3.0"\n    implementation "com.google.zxing:core:3.5.1"' "$BUILD_GRADLE"
fi

# ============= МОДЕЛИ ДАННЫХ =============
echo "[2/15] Creating data models..."

cat > "$KOTLIN_DIR/Product.kt" << 'EOF'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.*

@Entity(tableName = "products")
data class Product(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val barcode: String,
    val quantity: Int = 0,
    val minQuantity: Int = 5,
    val price: Double = 0.0,
    val category: String = "",
    val dateAdded: Date = Date(),
    val lastModified: Date = Date(),
    val description: String = "",
    val unit: String = "шт"
)
EOF

echo "[3/15] Creating warehouse operation model..."

cat > "$KOTLIN_DIR/WarehouseOperation.kt" << 'EOF'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.*

@Entity(tableName = "warehouse_operations")
data class WarehouseOperation(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val productId: Long,
    val operationType: String,
    val quantity: Int,
    val date: Date = Date(),
    val invoiceId: Long? = null,
    val notes: String = ""
)
EOF

echo "[4/15] Creating receipt data model..."

cat > "$KOTLIN_DIR/ReceiptData.kt" << 'EOF'
package com.example.fa_ksiegowy

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.*

@Entity(tableName = "receipts")
data class ReceiptData(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val date: Date = Date(),
    val amount: Double = 0.0,
    val vendor: String = "",
    val extractedText: String = "",
    val imageUri: String = "",
    val converted: Boolean = false,
    val entryId: Long? = null
)
EOF

# ============= DAO =============
echo "[5/15] Creating DAOs..."

cat > "$KOTLIN_DIR/ProductDao.kt" << 'EOF'
package com.example.fa_ksiegowy

import androidx.room.*

@Dao
interface ProductDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertProduct(product: Product): Long

    @Update
    suspend fun updateProduct(product: Product)

    @Delete
    suspend fun deleteProduct(product: Product)

    @Query("SELECT * FROM products ORDER BY name ASC")
    suspend fun getAllProducts(): List<Product>

    @Query("SELECT * FROM products WHERE id = :id")
    suspend fun getProductById(id: Long): Product?

    @Query("SELECT * FROM products WHERE barcode = :barcode")
    suspend fun getProductByBarcode(barcode: String): Product?

    @Query("SELECT * FROM products WHERE quantity <= minQuantity")
    suspend fun getLowStockProducts(): List<Product>

    @Query("SELECT * FROM products WHERE category = :category")
    suspend fun getProductsByCategory(category: String): List<Product>

    @Query("UPDATE products SET quantity = :quantity WHERE id = :id")
    suspend fun updateQuantity(id: Long, quantity: Int)

    @Query("DELETE FROM products WHERE id = :id")
    suspend fun deleteById(id: Long)
}
EOF

echo "[6/15] Creating warehouse operation DAO..."

cat > "$KOTLIN_DIR/WarehouseOperationDao.kt" << 'EOF'
package com.example.fa_ksiegowy

import androidx.room.*
import java.util.*

@Dao
interface WarehouseOperationDao {
    @Insert
    suspend fun insertOperation(operation: WarehouseOperation): Long

    @Query("SELECT * FROM warehouse_operations WHERE productId = :productId ORDER BY date DESC")
    suspend fun getOperationsByProduct(productId: Long): List<WarehouseOperation>

    @Query("SELECT * FROM warehouse_operations WHERE date BETWEEN :startDate AND :endDate ORDER BY date DESC")
    suspend fun getOperationsByDateRange(startDate: Date, endDate: Date): List<WarehouseOperation>

    @Query("SELECT * FROM warehouse_operations ORDER BY date DESC LIMIT 100")
    suspend fun getRecentOperations(): List<WarehouseOperation>

    @Delete
    suspend fun deleteOperation(operation: WarehouseOperation)
}
EOF

echo "[7/15] Creating receipt DAO..."

cat > "$KOTLIN_DIR/ReceiptDao.kt" << 'EOF'
package com.example.fa_ksiegowy

import androidx.room.*

@Dao
interface ReceiptDao {
    @Insert
    suspend fun insertReceipt(receipt: ReceiptData): Long

    @Update
    suspend fun updateReceipt(receipt: ReceiptData)

    @Query("SELECT * FROM receipts ORDER BY date DESC")
    suspend fun getAllReceipts(): List<ReceiptData>

    @Query("SELECT * FROM receipts WHERE converted = 0 ORDER BY date DESC")
    suspend fun getUnconvertedReceipts(): List<ReceiptData>

    @Delete
    suspend fun deleteReceipt(receipt: ReceiptData)
}
EOF

# ============= OCR =============
echo "[8/15] Creating OCR recognizer..."

cat > "$KOTLIN_DIR/OcrRecognizer.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.*
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCancellableCoroutine

class OcrRecognizer(private val context: Context) {
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    suspend fun recognizeText(bitmap: Bitmap): String = suspendCancellableCoroutine { continuation ->
        val image = InputImage.fromBitmap(bitmap, 0)
        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                continuation.resume(visionText.text)
            }
            .addOnFailureListener {
                continuation.resume("")
            }
    }

    fun parseReceiptData(text: String): ReceiptData {
        val lines = text.split("\n")
        var totalAmount = 0.0
        var vendor = ""

        for (line in lines) {
            val amountRegex = Regex("\\d+[.,]?\\d{2}|\\d+[.,]\\d+")
            val amount = amountRegex.find(line)?.value
            if (amount != null) {
                totalAmount = amount.replace(",", ".").toDoubleOrNull() ?: 0.0
            }
            if (vendor.isEmpty() && line.length > 3) {
                vendor = line.trim()
            }
        }

        return ReceiptData(
            amount = totalAmount,
            vendor = vendor,
            extractedText = text,
            date = Date()
        )
    }
}
EOF

# ============= WAREHOUSE MANAGER =============
echo "[9/15] Creating warehouse manager..."

cat > "$KOTLIN_DIR/WarehouseManager.kt" << 'EOF'
package com.example.fa_ksiegowy

class WarehouseManager(
    private val productDao: ProductDao,
    private val operationDao: WarehouseOperationDao
) {
    suspend fun addProductToWarehouse(product: Product) {
        productDao.insertProduct(product)
    }

    suspend fun removeProduct(productId: Long) {
        productDao.deleteById(productId)
    }

    suspend fun updateStock(productId: Long, quantity: Int, operationType: String = "UPDATE") {
        val product = productDao.getProductById(productId) ?: return
        val newQuantity = when (operationType) {
            "ADD" -> product.quantity + quantity
            "REMOVE", "SALE" -> product.quantity - quantity
            else -> quantity
        }

        if (newQuantity >= 0) {
            productDao.updateQuantity(productId, newQuantity)
            operationDao.insertOperation(
                WarehouseOperation(
                    productId = productId,
                    operationType = operationType,
                    quantity = quantity
                )
            )
        }
    }

    suspend fun getLowStockProducts(): List<Product> {
        return productDao.getLowStockProducts()
    }

    suspend fun getProductByBarcode(barcode: String): Product? {
        return productDao.getProductByBarcode(barcode)
    }

    suspend fun getAllProducts(): List<Product> {
        return productDao.getAllProducts()
    }
}
EOF

# ============= ACTIVITIES =============
echo "[10/15] Creating receipt scanner activity..."

cat > "$KOTLIN_DIR/ReceiptScannerActivity.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class ReceiptScannerActivity : BaseActivity() {
    private lateinit var previewView: PreviewView
    private lateinit var captureButton: Button
    private lateinit var resultText: TextView
    private lateinit var ocrRecognizer: OcrRecognizer
    private val CAMERA_PERMISSION_CODE = 101
    private val GALLERY_REQUEST_CODE = 102

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_receipt_scanner)

        captureButton = findViewById(R.id.btn_capture)
        resultText = findViewById(R.id.result_text)
        ocrRecognizer = OcrRecognizer(this)

        requestCameraPermission()

        captureButton.setOnClickListener {
            openCamera()
        }
    }

    private fun requestCameraPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
            }
        }
    }

    private fun openCamera() {
        val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
        startActivityForResult(intent, GALLERY_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == GALLERY_REQUEST_CODE && resultCode == RESULT_OK) {
            val imageUri: Uri? = data?.data
            if (imageUri != null) {
                val bitmap = MediaStore.Images.Media.getBitmap(contentResolver, imageUri)
                processReceiptImage(bitmap)
            }
        }
    }

    private fun processReceiptImage(bitmap: Bitmap) {
        lifecycleScope.launch {
            try {
                val recognizedText = ocrRecognizer.recognizeText(bitmap)
                val receiptData = ocrRecognizer.parseReceiptData(recognizedText)
                
                resultText.text = "Дата: ${receiptData.date}\nПродавец: ${receiptData.vendor}\nСумма: ${receiptData.amount}"

                val db = AppDatabase.getInstance(this@ReceiptScannerActivity)
                db.receiptDao().insertReceipt(receiptData)
                Toast.makeText(this@ReceiptScannerActivity, "Чек сохранен", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this@ReceiptScannerActivity, "Ошибка: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
EOF

echo "[11/15] Creating warehouse activity..."

cat > "$KOTLIN_DIR/WarehouseActivity.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.ListView
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class WarehouseActivity : BaseActivity() {
    private lateinit var listView: ListView
    private lateinit var addButton: Button
    private lateinit var scanButton: Button
    private lateinit var warehouseManager: WarehouseManager
    private var products = mutableListOf<Product>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_warehouse)

        listView = findViewById(R.id.products_list)
        addButton = findViewById(R.id.btn_add_product)
        scanButton = findViewById(R.id.btn_scan_barcode)

        val db = AppDatabase.getInstance(this)
        warehouseManager = WarehouseManager(db.productDao(), db.operationDao())

        addButton.setOnClickListener {
            startActivity(Intent(this, AddProductActivity::class.java))
        }

        scanButton.setOnClickListener {
            startActivity(Intent(this, BarcodeScannerActivity::class.java))
        }

        loadProducts()
    }

    override fun onResume() {
        super.onResume()
        loadProducts()
    }

    private fun loadProducts() {
        lifecycleScope.launch {
            products.clear()
            products.addAll(warehouseManager.getAllProducts())
            
            runOnUiThread {
                val adapter = ProductAdapter(this@WarehouseActivity, products)
                listView.adapter = adapter
            }
        }
    }
}
EOF

echo "[12/15] Creating barcode scanner activity..."

cat > "$KOTLIN_DIR/BarcodeScannerActivity.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.journeyapps.barcodescanner.BarcodeCallback
import com.journeyapps.barcodescanner.BarcodeResult
import com.journeyapps.barcodescanner.DecoratedBarcodeView
import kotlinx.coroutines.launch

class BarcodeScannerActivity : BaseActivity() {
    private lateinit var barcodeView: DecoratedBarcodeView
    private val CAMERA_PERMISSION_CODE = 101

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_barcode_scanner)

        barcodeView = findViewById(R.id.barcode_scanner)
        requestCameraPermission()

        barcodeView.decodeContinuous(object : BarcodeCallback {
            override fun barcodeResult(result: BarcodeResult?) {
                if (result != null && !result.text.isEmpty()) {
                    processBarcode(result.text)
                }
            }
            override fun possibleResultPoints(resultPoints: MutableList<com.google.zxing.ResultPoint>?) {}
        })
    }

    private fun requestCameraPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
            } else {
                barcodeView.resume()
            }
        }
    }

    private fun processBarcode(barcode: String) {
        lifecycleScope.launch {
            val db = AppDatabase.getInstance(this@BarcodeScannerActivity)
            val product = db.productDao().getProductByBarcode(barcode)

            if (product != null) {
                Toast.makeText(this@BarcodeScannerActivity, "Найден: ${product.name}", Toast.LENGTH_SHORT).show()
                db.productDao().updateQuantity(product.id, product.quantity + 1)
            } else {
                Toast.makeText(this@BarcodeScannerActivity, "Товар не найден", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        barcodeView.resume()
    }

    override fun onPause() {
        super.onPause()
        barcodeView.pause()
    }
}
EOF

echo "[13/15] Creating add product activity..."

cat > "$KOTLIN_DIR/AddProductActivity.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.Spinner
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import java.util.*

class AddProductActivity : BaseActivity() {
    private lateinit var nameInput: EditText
    private lateinit var barcodeInput: EditText
    private lateinit var quantityInput: EditText
    private lateinit var priceInput: EditText
    private lateinit var minQuantityInput: EditText
    private lateinit var categorySpinner: Spinner
    private lateinit var unitInput: EditText
    private lateinit var saveButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_product)

        nameInput = findViewById(R.id.et_product_name)
        barcodeInput = findViewById(R.id.et_barcode)
        quantityInput = findViewById(R.id.et_quantity)
        priceInput = findViewById(R.id.et_price)
        minQuantityInput = findViewById(R.id.et_min_quantity)
        categorySpinner = findViewById(R.id.spinner_category)
        unitInput = findViewById(R.id.et_unit)
        saveButton = findViewById(R.id.btn_save_product)

        setupCategorySpinner()

        saveButton.setOnClickListener {
            saveProduct()
        }
    }

    private fun setupCategorySpinner() {
        val categories = arrayOf("Выберите категорию", "Продукты", "Напитки", "Канцелярия", "Электроника", "Одежда", "Прочее")
        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, categories)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        categorySpinner.adapter = adapter
    }

    private fun saveProduct() {
        val name = nameInput.text.toString().trim()
        val barcode = barcodeInput.text.toString().trim()
        val quantity = quantityInput.text.toString().toIntOrNull() ?: 0
        val price = priceInput.text.toString().toDoubleOrNull() ?: 0.0
        val minQuantity = minQuantityInput.text.toString().toIntOrNull() ?: 5
        val category = categorySpinner.selectedItem.toString()
        val unit = unitInput.text.toString().trim().ifEmpty { "шт" }

        if (name.isEmpty()) {
            Toast.makeText(this, "Введите название товара", Toast.LENGTH_SHORT).show()
            return
        }

        val product = Product(name = name, barcode = barcode, quantity = quantity, price = price, minQuantity = minQuantity, category = category, unit = unit, dateAdded = Date(), lastModified = Date())

        lifecycleScope.launch {
            try {
                val db = AppDatabase.getInstance(this@AddProductActivity)
                db.productDao().insertProduct(product)
                Toast.makeText(this@AddProductActivity, "Товар добавлен", Toast.LENGTH_SHORT).show()
                finish()
            } catch (e: Exception) {
                Toast.makeText(this@AddProductActivity, "Ошибка: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
EOF

echo "[14/15] Creating product adapter..."

cat > "$KOTLIN_DIR/ProductAdapter.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.TextView

class ProductAdapter(context: Context, private val products: List<Product>) : ArrayAdapter<Product>(context, 0, products) {
    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        var view = convertView
        if (view == null) {
            view = LayoutInflater.from(context).inflate(R.layout.item_product, parent, false)
        }

        val product = products[position]
        val nameView: TextView = view!!.findViewById(R.id.product_name)
        val quantityView: TextView = view.findViewById(R.id.product_quantity)
        val priceView: TextView = view.findViewById(R.id.product_price)

        nameView.text = product.name
        quantityView.text = "Кол-во: ${product.quantity} ${product.unit}"
        priceView.text = "Цена: ${product.price}"

        if (product.quantity <= product.minQuantity) {
            view.setBackgroundColor(android.graphics.Color.parseColor("#FFEB3B"))
        }

        return view
    }
}
EOF

echo "[15/15] Creating layouts..."

mkdir -p "$LAYOUT_DIR"

cat > "$LAYOUT_DIR/activity_receipt_scanner.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">
    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="Сканирование Чека" android:textSize="20sp" android:textStyle="bold" android:layout_marginBottom="16dp" />
    <Button android:id="@+id/btn_capture" android:layout_width="match_parent" android:layout_height="wrap_content" android:text="Выбрать Фото" />
    <TextView android:id="@+id/result_text" android:layout_width="match_parent" android:layout_height="match_parent" android:text="Результат сканирования" android:padding="16dp" />
</LinearLayout>
EOF

cat > "$LAYOUT_DIR/activity_warehouse.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">
    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="Управление Складом" android:textSize="20sp" android:textStyle="bold" android:layout_marginBottom="16dp" />
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="16dp">
        <Button android:id="@+id/btn_add_product" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:text="Добавить Товар" android:layout_marginEnd="8dp" />
        <Button android:id="@+id/btn_scan_barcode" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:text="Сканировать" />
    </LinearLayout>
    <ListView android:id="@+id/products_list" android:layout_width="match_parent" android:layout_height="match_parent" />
</LinearLayout>
EOF

cat > "$LAYOUT_DIR/activity_barcode_scanner.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">
    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="Сканирование Штрих-кодов" android:textSize="20sp" android:textStyle="bold" android:padding="16dp" />
    <com.journeyapps.barcodescanner.DecoratedBarcodeView android:id="@+id/barcode_scanner" android:layout_width="match_parent" android:layout_height="match_parent" />
</LinearLayout>
EOF

cat > "$LAYOUT_DIR/activity_add_product.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="vertical" android:padding="16dp">
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="Добавление Товара" android:textSize="20sp" android:textStyle="bold" android:layout_marginBottom="16dp" />
        <EditText android:id="@+id/et_product_name" android:layout_width="match_parent" android:layout_height="wrap_content" android:hint="Название товара" android:inputType="text" android:layout_marginBottom="8dp" />
        <EditText android:id="@+id/et_barcode" android:layout_width="match_parent" android:layout_height="wrap_content" android:hint="Штрих-код" android:inputType="text" android:layout_marginBottom="8dp" />
        <EditText android:id="@+id/et_quantity" android:layout_width="match_parent" android:layout_height="wrap_content" android:hint="Количество" android:inputType="number" android:layout_marginBottom="8dp" />
        <EditText android:id="@+id/et_price" android:layout_width="match_parent" android:layout_height="wrap_content" android:hint="Цена" android:inputType="numberDecimal" android:layout_marginBottom="8dp" />
        <EditText android:id="@+id/et_min_quantity" android:layout_width="match_parent" android:layout_height="wrap_content" android:hint="Минимальное количество" android:inputType="number" android:layout_marginBottom="8dp" />
        <EditText android:id="@+id/et_unit" android:layout_width="match_parent" android:layout_height="wrap_content" android:hint="Единица измерения" android:inputType="text" android:layout_marginBottom="8dp" />
        <Spinner android:id="@+id/spinner_category" android:layout_width="match_parent" android:layout_height="wrap_content" android:layout_marginBottom="16dp" />
        <Button android:id="@+id/btn_save_product" android:layout_width="match_parent" android:layout_height="wrap_content" android:text="Добавить Товар" />
    </LinearLayout>
</ScrollView>
EOF

cat > "$LAYOUT_DIR/item_product.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="12dp">
    <TextView android:id="@+id/product_name" android:layout_width="wrap_content" android:layout_height="wrap_content" android:textSize="16sp" android:textStyle="bold" />
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginTop="4dp">
        <TextView android:id="@+id/product_quantity" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:textSize="14sp" />
        <TextView android:id="@+id/product_price" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:textSize="14sp" />
    </LinearLayout>
</LinearLayout>
EOF

# ============= РАЗРЕШЕНИЯ И АКТИВИТИ В МАНИФЕСТЕ =============
echo "Adding permissions and activities..."

if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
    sed -i '/<\/manifest>/i\    <uses-permission android:name="android.permission.CAMERA" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />' "$MANIFEST"
fi

if ! grep -q 'ReceiptScannerActivity' "$MANIFEST"; then
    sed -i '/<\/application>/i\        <activity android:name=".ReceiptScannerActivity" />\n        <activity android:name=".WarehouseActivity" />\n        <activity android:name=".BarcodeScannerActivity" />\n        <activity android:name=".AddProductActivity" />' "$MANIFEST"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✓ Installation Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Added Features:"
echo "  ✓ OCR Receipt Scanner (Google ML Kit)"
echo "  ✓ Warehouse Management"
echo "  ✓ Barcode Scanner (ZXing)"
echo "  ✓ Product Database"
echo "  ✓ Stock Tracking"
echo ""
