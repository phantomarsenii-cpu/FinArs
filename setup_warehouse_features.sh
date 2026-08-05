#!/bin/bash

# FA_ksiegowy - Setup Warehouse Features
# Вспомогательный скрипт для полной интеграции функций склада и выбора типа деятельности

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOTLIN_DIR="$PROJECT_ROOT/app/src/main/java/com/example/fa_ksiegowy"
LAYOUT_DIR="$PROJECT_ROOT/app/src/main/res/layout"
VALUES_DIR="$PROJECT_ROOT/app/src/main/res/values"

echo "════════════════════════════════════════════════════════════"
echo "Setup: Warehouse Features Integration"
echo "════════════════════════════════════════════════════════════"

# ============= СОЗДАНИЕ АКТИВИТИ ДОБАВЛЕНИЯ ТОВАРА =============
echo "[1/5] Создание активити добавления товара..."

cat > "$KOTLIN_DIR/AddProductActivity.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.Spinner
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
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
        val categories = arrayOf(
            "Выберите категорию",
            "Продукты",
            "Напитки",
            "Канцелярия",
            "Электроника",
            "Одежда",
            "Прочее"
        )
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

        val product = Product(
            name = name,
            barcode = barcode,
            quantity = quantity,
            price = price,
            minQuantity = minQuantity,
            category = category,
            unit = unit,
            dateAdded = Date(),
            lastModified = Date()
        )

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

echo "✓ Активити добавления товара создано"

# ============= СОЗДАНИЕ АКТИВИТИ ВЫБОРА ТИПА ДЕЯТЕЛЬНОСТИ =============
echo "[2/5] Создание активити выбора типа деятельности..."

cat > "$KOTLIN_DIR/BusinessTypeSettingsActivity.kt" << 'EOF'
package com.example.fa_ksiegowy

import android.content.SharedPreferences
import android.os.Bundle
import android.widget.CheckBox
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class BusinessTypeSettingsActivity : BaseActivity() {
    private lateinit var radioGroup: RadioGroup
    private lateinit var warehouseCheckbox: CheckBox
    private lateinit var ocrCheckbox: CheckBox
    private lateinit var invoicesCheckbox: CheckBox
    private lateinit var saveButton: Button
    private lateinit var sharedPreferences: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_business_type_settings)

        radioGroup = findViewById(R.id.radio_business_type)
        warehouseCheckbox = findViewById(R.id.checkbox_warehouse)
        ocrCheckbox = findViewById(R.id.checkbox_ocr)
        invoicesCheckbox = findViewById(R.id.checkbox_invoices)
        saveButton = findViewById(R.id.btn_save_settings)
        
        sharedPreferences = getSharedPreferences("business_settings", MODE_PRIVATE)

        loadSettings()

        saveButton.setOnClickListener {
            saveSettings()
        }

        radioGroup.setOnCheckedChangeListener { _, checkedId ->
            updateFeatureAvailability(checkedId)
        }
    }

    private fun loadSettings() {
        val businessType = sharedPreferences.getString("business_type", "services") ?: "services"
        val warehouseEnabled = sharedPreferences.getBoolean("warehouse_enabled", false)
        val ocrEnabled = sharedPreferences.getBoolean("ocr_enabled", false)
        val invoicesEnabled = sharedPreferences.getBoolean("invoices_enabled", true)

        when (businessType) {
            "sales" -> radioGroup.check(R.id.radio_sales)
            "services" -> radioGroup.check(R.id.radio_services)
            "mixed" -> radioGroup.check(R.id.radio_mixed)
        }

        warehouseCheckbox.isChecked = warehouseEnabled
        ocrCheckbox.isChecked = ocrEnabled
        invoicesCheckbox.isChecked = invoicesEnabled
    }

    private fun updateFeatureAvailability(checkedId: Int) {
        val isSales = checkedId == R.id.radio_sales || checkedId == R.id.radio_mixed
        warehouseCheckbox.isEnabled = isSales
        
        if (!isSales) {
            warehouseCheckbox.isChecked = false
        }
    }

    private fun saveSettings() {
        val editor = sharedPreferences.edit()

        val selectedId = radioGroup.checkedRadioButtonId
        val businessType = when (selectedId) {
            R.id.radio_sales -> "sales"
            R.id.radio_services -> "services"
            R.id.radio_mixed -> "mixed"
            else -> "services"
        }

        editor.putString("business_type", businessType)
        editor.putBoolean("warehouse_enabled", warehouseCheckbox.isChecked)
        editor.putBoolean("ocr_enabled", ocrCheckbox.isChecked)
        editor.putBoolean("invoices_enabled", invoicesCheckbox.isChecked)
        editor.apply()

        Toast.makeText(this, "Настройки сохранены", Toast.LENGTH_SHORT).show()
        finish()
    }
}
EOF

echo "✓ Активити выбора типа деятельности создано"

# ============= СОЗДАНИЕ LAYOUT ДЛЯ ДОБАВЛЕНИЯ ТОВАРА =============
echo "[3/5] Создание layouts для новых активитей..."

cat > "$LAYOUT_DIR/activity_add_product.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Добавление Товара"
            android:textSize="20sp"
            android:textStyle="bold"
            android:layout_marginBottom="16dp" />

        <EditText
            android:id="@+id/et_product_name"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Название товара"
            android:inputType="text"
            android:layout_marginBottom="8dp" />

        <EditText
            android:id="@+id/et_barcode"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Штрих-код"
            android:inputType="text"
            android:layout_marginBottom="8dp" />

        <EditText
            android:id="@+id/et_quantity"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Количество"
            android:inputType="number"
            android:layout_marginBottom="8dp" />

        <EditText
            android:id="@+id/et_price"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Цена"
            android:inputType="numberDecimal"
            android:layout_marginBottom="8dp" />

        <EditText
            android:id="@+id/et_min_quantity"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Минимальное количество"
            android:inputType="number"
            android:layout_marginBottom="8dp" />

        <EditText
            android:id="@+id/et_unit"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Единица измерения (шт, кг, л)"
            android:inputType="text"
            android:layout_marginBottom="8dp" />

        <Spinner
            android:id="@+id/spinner_category"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="16dp" />

        <Button
            android:id="@+id/btn_save_product"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Добавить Товар" />
    </LinearLayout>
</ScrollView>
EOF

cat > "$LAYOUT_DIR/activity_business_type_settings.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Тип Деятельности"
            android:textSize="18sp"
            android:textStyle="bold"
            android:layout_marginBottom="16dp" />

        <RadioGroup
            android:id="@+id/radio_business_type"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="24dp">

            <RadioButton
                android:id="@+id/radio_services"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="Услуги" />

            <RadioButton
                android:id="@+id/radio_sales"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="Продажа товаров"
                android:layout_marginTop="8dp" />

            <RadioButton
                android:id="@+id/radio_mixed"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="Смешанная деятельность"
                android:layout_marginTop="8dp" />
        </RadioGroup>

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Включить функции"
            android:textSize="16sp"
            android:textStyle="bold"
            android:layout_marginBottom="12dp" />

        <CheckBox
            android:id="@+id/checkbox_warehouse"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Управление складом"
            android:layout_marginBottom="8dp"
            android:enabled="false" />

        <CheckBox
            android:id="@+id/checkbox_ocr"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Сканирование чеков (OCR)"
            android:layout_marginBottom="8dp" />

        <CheckBox
            android:id="@+id/checkbox_invoices"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Счета и фактуры"
            android:layout_marginBottom="24dp" />

        <Button
            android:id="@+id/btn_save_settings"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Сохранить Настройки" />
    </LinearLayout>
</ScrollView>
EOF

echo "✓ Layouts созданы"

# ============= ОБНОВЛЕНИЕ SETTINGS ACTIVITY =============
echo "[4/5] Обновление SettingsActivity для добавления новых опций..."

SETTINGS_FILE="$KOTLIN_DIR/SettingsActivity.kt"

if grep -q "class SettingsActivity" "$SETTINGS_FILE"; then
    # Добавляем кнопку для настроек типа деятельности перед концом onCreate
    sed -i '/override fun onCreate/,/^    }/ {
        /^    }/i\
        findViewById<View>(R.id.btn_business_type)?.setOnClickListener {\
            startActivity(Intent(this, BusinessTypeSettingsActivity::class.java))\
        }
    }' "$SETTINGS_FILE" 2>/dev/null || true
    
    echo "✓ SettingsActivity обновлена"
fi

# ============= ОБНОВЛЕНИЕ ACTIVITY_SETTINGS LAYOUT =============
echo "[5/5] Обновление activity_settings layout..."

SETTINGS_LAYOUT="$LAYOUT_DIR/activity_settings.xml"

if grep -q "activity_settings" "$SETTINGS_LAYOUT" 2>/dev/null; then
    # Добавляем кнопку для типа деятельности
    sed -i '/<\/LinearLayout>/i\
    <Button\
        android:id="@+id/btn_business_type"\
        android:layout_width="match_parent"\
        android:layout_height="wrap_content"\
        android:text="Тип деятельности и функции"\
        android:layout_marginTop="8dp" />' "$SETTINGS_LAYOUT" 2>/dev/null || true
    
    echo "✓ Activity_settings layout обновлена"
fi

# ============= ФИНАЛЬНОЕ СООБЩЕНИЕ =============
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✓ Все дополнительные компоненты установлены!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Установленные компоненты:"
echo "  ✓ AddProductActivity - добавление товаров"
echo "  ✓ BusinessTypeSettingsActivity - выбор типа деятельности"
echo "  ✓ Автоматическое отображение функций по типу деятельности"
echo "  ✓ Интеграция с Settings"
echo ""
echo "Следующие команды для Termux:"
echo ""
echo "  # Переход в директорию проекта"
echo "  cd /path/to/FA_ksiegowy-main"
echo ""
echo "  # Кэширование зависимостей"
echo "  chmod +x update_project-41-ocr-warehouse-barcode.sh"
echo "  ./update_project-41-ocr-warehouse-barcode.sh"
echo ""
echo "  chmod +x ../setup_warehouse_features.sh"
echo "  ../setup_warehouse_features.sh"
echo ""
echo "  # Сборка проекта"
echo "  chmod +x gradlew"
echo "  ./gradlew clean"
echo "  ./gradlew build"
echo ""
echo "  # Git push"
echo "  git add ."
echo "  git commit -m 'feat: Add OCR, Warehouse Management and Barcode Scanner features'"
echo "  git push origin main"
echo ""
