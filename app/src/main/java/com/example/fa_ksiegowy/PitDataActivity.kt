package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.Toast

/** Форма личных данных, нужных для отчёта PIT-36 (см. Pit36PdfGenerator, Pit36FormFiller). */
class PitDataActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pit_data)

        val data = PitDataStore.load(this)
        findViewById<EditText>(R.id.et_first_name).setText(data.firstName)
        findViewById<EditText>(R.id.et_last_name).setText(data.lastName)
        findViewById<EditText>(R.id.et_pesel).setText(data.pesel)
        findViewById<EditText>(R.id.et_street).setText(data.street)
        findViewById<EditText>(R.id.et_house_number).setText(data.houseNumber)
        findViewById<EditText>(R.id.et_apartment_number).setText(data.apartmentNumber)
        findViewById<EditText>(R.id.et_voivodeship).setText(data.voivodeship)
        findViewById<EditText>(R.id.et_county).setText(data.county)
        findViewById<EditText>(R.id.et_commune).setText(data.commune)
        findViewById<EditText>(R.id.et_postal_code).setText(data.postalCode)
        findViewById<EditText>(R.id.et_city).setText(data.city)
        findViewById<EditText>(R.id.et_tax_office).setText(data.taxOffice)
        findViewById<EditText>(R.id.et_children_count).setText(if (data.childrenCount > 0) data.childrenCount.toString() else "")
        findViewById<EditText>(R.id.et_internet_relief).setText(if (data.internetRelief > 0) data.internetRelief.toString() else "")
        findViewById<EditText>(R.id.et_ikze).setText(if (data.ikzeContribution > 0) data.ikzeContribution.toString() else "")
        findViewById<EditText>(R.id.et_donations).setText(if (data.donations > 0) data.donations.toString() else "")
        findViewById<CheckBox>(R.id.cb_joint_spouse).isChecked = data.jointWithSpouse

        findViewById<Button>(R.id.btn_save_pit_data).setOnClickListener { save() }
    }

    private fun save() {
        fun text(id: Int) = findViewById<EditText>(id).text.toString().trim()
        fun number(id: Int) = text(id).replace(",", ".").toDoubleOrNull() ?: 0.0
        fun intNumber(id: Int) = text(id).toIntOrNull() ?: 0

        val firstName = text(R.id.et_first_name)
        val lastName = text(R.id.et_last_name)
        val taxOffice = text(R.id.et_tax_office)

        if (firstName.isBlank() || lastName.isBlank() || taxOffice.isBlank()) {
            Toast.makeText(this, getString(R.string.pit_data_required_error), Toast.LENGTH_LONG).show()
            return
        }

        val data = PitPersonalData(
            firstName = firstName,
            lastName = lastName,
            pesel = text(R.id.et_pesel),
            street = text(R.id.et_street),
            houseNumber = text(R.id.et_house_number),
            apartmentNumber = text(R.id.et_apartment_number),
            voivodeship = text(R.id.et_voivodeship),
            county = text(R.id.et_county),
            commune = text(R.id.et_commune),
            postalCode = text(R.id.et_postal_code),
            city = text(R.id.et_city),
            taxOffice = taxOffice,
            childrenCount = intNumber(R.id.et_children_count),
            internetRelief = number(R.id.et_internet_relief),
            ikzeContribution = number(R.id.et_ikze),
            donations = number(R.id.et_donations),
            jointWithSpouse = findViewById<CheckBox>(R.id.cb_joint_spouse).isChecked
        )
        PitDataStore.save(this, data)
        Toast.makeText(this, getString(R.string.saved), Toast.LENGTH_SHORT).show()
        finish()
    }
}
