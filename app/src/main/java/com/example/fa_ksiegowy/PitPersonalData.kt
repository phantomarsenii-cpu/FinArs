package com.example.fa_ksiegowy

import android.content.Context

/**
 * Личные данные, нужные, чтобы правильно заполнить PIT-36 (имя/фамилия,
 * адрес, urząd skarbowy) и базовые данные для льгот (PIT/O). Хранится
 * локально в SharedPreferences — как и остальные настройки приложения.
 * Ничего не отправляется никуда за пределы устройства.
 */
data class PitPersonalData(
    val firstName: String = "",
    val lastName: String = "",
    val pesel: String = "",
    val street: String = "",
    val houseNumber: String = "",
    val apartmentNumber: String = "",
    val voivodeship: String = "",
    val county: String = "",
    val commune: String = "",
    val postalCode: String = "",
    val city: String = "",
    val taxOffice: String = "",
    val childrenCount: Int = 0,
    val internetRelief: Double = 0.0,
    val ikzeContribution: Double = 0.0,
    val donations: Double = 0.0,
    val jointWithSpouse: Boolean = false,
    // Данные супруга(и) — заполняются только если jointWithSpouse == true.
    val spouseIsNip: Boolean = true, // true = NIP, false = PESEL
    val spouseId: String = "",
    val spouseFirstName: String = "",
    val spouseLastName: String = "",
    val spouseBirthDate: String = "",
    val spouseIncome: Double = 0.0
) {
    val isComplete: Boolean
        get() = firstName.isNotBlank() && lastName.isNotBlank() && taxOffice.isNotBlank()
}

object PitDataStore {
    private const val PREFS = "pit_data"

    fun load(context: Context): PitPersonalData {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return PitPersonalData(
            firstName = p.getString("firstName", "") ?: "",
            lastName = p.getString("lastName", "") ?: "",
            pesel = p.getString("pesel", "") ?: "",
            street = p.getString("street", "") ?: "",
            houseNumber = p.getString("houseNumber", "") ?: "",
            apartmentNumber = p.getString("apartmentNumber", "") ?: "",
            voivodeship = p.getString("voivodeship", "") ?: "",
            county = p.getString("county", "") ?: "",
            commune = p.getString("commune", "") ?: "",
            postalCode = p.getString("postalCode", "") ?: "",
            city = p.getString("city", "") ?: "",
            taxOffice = p.getString("taxOffice", "") ?: "",
            childrenCount = p.getInt("childrenCount", 0),
            internetRelief = p.getFloat("internetRelief", 0f).toDouble(),
            ikzeContribution = p.getFloat("ikzeContribution", 0f).toDouble(),
            donations = p.getFloat("donations", 0f).toDouble(),
            jointWithSpouse = p.getBoolean("jointWithSpouse", false),
            spouseIsNip = p.getBoolean("spouseIsNip", true),
            spouseId = p.getString("spouseId", "") ?: "",
            spouseFirstName = p.getString("spouseFirstName", "") ?: "",
            spouseLastName = p.getString("spouseLastName", "") ?: "",
            spouseBirthDate = p.getString("spouseBirthDate", "") ?: "",
            spouseIncome = p.getFloat("spouseIncome", 0f).toDouble()
        )
    }

    fun save(context: Context, data: PitPersonalData) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("firstName", data.firstName)
            .putString("lastName", data.lastName)
            .putString("pesel", data.pesel)
            .putString("street", data.street)
            .putString("houseNumber", data.houseNumber)
            .putString("apartmentNumber", data.apartmentNumber)
            .putString("voivodeship", data.voivodeship)
            .putString("county", data.county)
            .putString("commune", data.commune)
            .putString("postalCode", data.postalCode)
            .putString("city", data.city)
            .putString("taxOffice", data.taxOffice)
            .putInt("childrenCount", data.childrenCount)
            .putFloat("internetRelief", data.internetRelief.toFloat())
            .putFloat("ikzeContribution", data.ikzeContribution.toFloat())
            .putFloat("donations", data.donations.toFloat())
            .putBoolean("jointWithSpouse", data.jointWithSpouse)
            .putBoolean("spouseIsNip", data.spouseIsNip)
            .putString("spouseId", data.spouseId)
            .putString("spouseFirstName", data.spouseFirstName)
            .putString("spouseLastName", data.spouseLastName)
            .putString("spouseBirthDate", data.spouseBirthDate)
            .putFloat("spouseIncome", data.spouseIncome.toFloat())
            .apply()
    }
}
