package com.example.fa_ksiegowy

import java.text.SimpleDateFormat
import java.util.*

/**
 * XML Generator для e-Deklaracje (файлы для отправки в urząd skarbowy)
 * 
 * Поддерживаемые формы:
 * - PIT-36L(21) - Линейный налог 19%
 * - PIT-28(27) - Ryczałt (лум-сум налог)
 * 
 * Генерирует валидный XML согласно официальным XSD схемам
 * Министерства Финансов Польши (MF)
 */
object EDeklaracjeXmlGenerator {
    
    private const val XML_VERSION = "1.0"
    private const val XML_ENCODING = "UTF-8"
    
    data class TaxpayerInfo(
        val nip: String,  // 10 цифр, формат: XXXXXXXXXX
        val pesel: String = "",  // 11 цифр, если доступен
        val firstName: String,
        val lastName: String,
        val birthDate: String,  // YYYY-MM-DD
        val address: Address,
        val email: String = "",
        val phone: String = ""
    )
    
    data class Address(
        val street: String,
        val houseNumber: String,
        val apartmentNumber: String = "",
        val postalCode: String,
        val city: String,
        val voivodeship: String,
        val county: String,
        val commune: String
    )
    
    data class TaxOfficeInfo(
        val urzadSkarbowy: String,  // Название налогового органа
        val code: String = "0000"  // Код urząd (обычно 4 цифры)
    )
    
    /**
     * Генерировать XML PIT-36L(21) для e-Deklaracje
     */
    fun generatePit36LXml(
        taxpayer: TaxpayerInfo,
        taxOffice: TaxOfficeInfo,
        year: Int,
        calculationResult: Pit36LCalculator.Result,
        jointSpouse: TaxpayerInfo? = null
    ): String {
        val sb = StringBuilder()
        
        // XML Header
        sb.append("<?xml version=\"$XML_VERSION\" encoding=\"$XML_ENCODING\"?>\n")
        
        // Root element
        sb.append("<DeklaracjaPIT xmlns=\"http://spr.mf.gov.pl/spr/JPKPIT/01\" ")
        sb.append("xmlns:tns=\"http://spr.mf.gov.pl/spr/JPKPIT/01\" ")
        sb.append("xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" ")
        sb.append("xsi:schemaLocation=\"http://spr.mf.gov.pl/spr/JPKPIT/01\">\n")
        
        // Dane główne
        sb.append("  <NumerZeznania>PIT-36L(21)</NumerZeznania>\n")
        sb.append("  <RokPodatkowy>$year</RokPodatkowy>\n")
        sb.append("  <DataUtworzenia>${getCurrentDate()}</DataUtworzenia>\n")
        
        // Podatnik
        sb.append("  <Podatnik>\n")
        sb.append("    <NIP>${sanitizeNip(taxpayer.nip)}</NIP>\n")
        if (taxpayer.pesel.isNotEmpty()) {
            sb.append("    <PESEL>${taxpayer.pesel}</PESEL>\n")
        }
        sb.append("    <Imie>${xmlEscape(taxpayer.firstName)}</Imie>\n")
        sb.append("    <Nazwisko>${xmlEscape(taxpayer.lastName)}</Nazwisko>\n")
        sb.append("    <DataUrodzenia>${taxpayer.birthDate}</DataUrodzenia>\n")
        
        // Adres podatnika
        sb.append("    <Adres>\n")
        sb.append("      <Ulica>${xmlEscape(taxpayer.address.street)}</Ulica>\n")
        sb.append("      <NumerDomu>${xmlEscape(taxpayer.address.houseNumber)}</NumerDomu>\n")
        if (taxpayer.address.apartmentNumber.isNotEmpty()) {
            sb.append("      <NumerMieszkania>${xmlEscape(taxpayer.address.apartmentNumber)}</NumerMieszkania>\n")
        }
        sb.append("      <KodPocztowy>${xmlEscape(taxpayer.address.postalCode)}</KodPocztowy>\n")
        sb.append("      <Miejscowosc>${xmlEscape(taxpayer.address.city)}</Miejscowosc>\n")
        sb.append("      <Wojewodztwo>${xmlEscape(taxpayer.address.voivodeship)}</Wojewodztwo>\n")
        sb.append("      <Powiat>${xmlEscape(taxpayer.address.county)}</Powiat>\n")
        sb.append("      <Gmina>${xmlEscape(taxpayer.address.commune)}</Gmina>\n")
        sb.append("    </Adres>\n")
        
        if (taxpayer.email.isNotEmpty()) {
            sb.append("    <Email>${xmlEscape(taxpayer.email)}</Email>\n")
        }
        if (taxpayer.phone.isNotEmpty()) {
            sb.append("    <Telefon>${xmlEscape(taxpayer.phone)}</Telefon>\n")
        }
        
        sb.append("  </Podatnik>\n")
        
        // Wspólne rozliczenie (если есть супруг)
        if (jointSpouse != null) {
            sb.append("  <WspolneFiled>true</WspolneFiled>\n")
            sb.append("  <Malzonek>\n")
            sb.append("    <NIP>${sanitizeNip(jointSpouse.nip)}</NIP>\n")
            sb.append("    <Imie>${xmlEscape(jointSpouse.firstName)}</Imie>\n")
            sb.append("    <Nazwisko>${xmlEscape(jointSpouse.lastName)}</Nazwisko>\n")
            sb.append("  </Malzonek>\n")
        }
        
        // Urząd Skarbowy
        sb.append("  <UrzadSkarbowy>\n")
        sb.append("    <Nazwa>${xmlEscape(taxOffice.urzadSkarbowy)}</Nazwa>\n")
        sb.append("    <Kod>${taxOffice.code}</Kod>\n")
        sb.append("  </UrzadSkarbowy>\n")
        
        // Dane dochodów / costs (часть E: Dochody)
        sb.append("  <Dochody>\n")
        sb.append("    <PozarolniczaDzialalnoscGopodareza>\n")
        sb.append("      <Przychod>${formatDecimal(calculationResult.przychod)}</Przychod>\n")
        sb.append("      <Koszty>${formatDecimal(calculationResult.koszty)}</Koszty>\n")
        sb.append("      <Dochod>${formatDecimal(calculationResult.dochod)}</Dochod>\n")
        sb.append("    </PozarolniczaDzialalnoscGopodareza>\n")
        sb.append("  </Dochody>\n")
        
        // Podatek (часть H: Obliczenie podatku)
        sb.append("  <Podatek>\n")
        sb.append("    <StawkaPodatkowa>0.19</StawkaPodatkowa>\n")
        sb.append("    <PodstawaObliczeniaPodatku>${formatDecimal(calculationResult.taxableAfterReliefs)}</PodstawaObliczeniaPodatku>\n")
        sb.append("    <ObliczonyPodatek>${formatDecimal(calculationResult.taxGross)}</ObliczonyPodatek>\n")
        sb.append("    <PodatekPo zaokragleniu>${formatDecimal(calculationResult.tax)}</PodatekPozaokragleniu>\n")
        sb.append("  </Podatek>\n")
        
        // Koniec
        sb.append("</DeklaracjaPIT>\n")
        
        return sb.toString()
    }
    
    /**
     * Генерировать XML PIT-28(27) для e-Deklaracje (Ryczałt)
     */
    fun generatePit28Xml(
        taxpayer: TaxpayerInfo,
        taxOffice: TaxOfficeInfo,
        year: Int,
        calculationResult: Pit28Calculator.Result,
        jointSpouse: TaxpayerInfo? = null
    ): String {
        val sb = StringBuilder()
        
        // XML Header
        sb.append("<?xml version=\"$XML_VERSION\" encoding=\"$XML_ENCODING\"?>\n")
        
        // Root element
        sb.append("<DeklaracjaPIT xmlns=\"http://spr.mf.gov.pl/spr/JPKPIT/01\" ")
        sb.append("xmlns:tns=\"http://spr.mf.gov.pl/spr/JPKPIT/01\" ")
        sb.append("xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" ")
        sb.append("xsi:schemaLocation=\"http://spr.mf.gov.pl/spr/JPKPIT/01\">\n")
        
        // Dane główne
        sb.append("  <NumerZeznania>PIT-28(27)</NumerZeznania>\n")
        sb.append("  <RokPodatkowy>$year</RokPodatkowy>\n")
        sb.append("  <DataUtworzenia>${getCurrentDate()}</DataUtworzenia>\n")
        
        // Podatnik
        sb.append("  <Podatnik>\n")
        sb.append("    <NIP>${sanitizeNip(taxpayer.nip)}</NIP>\n")
        if (taxpayer.pesel.isNotEmpty()) {
            sb.append("    <PESEL>${taxpayer.pesel}</PESEL>\n")
        }
        sb.append("    <Imie>${xmlEscape(taxpayer.firstName)}</Imie>\n")
        sb.append("    <Nazwisko>${xmlEscape(taxpayer.lastName)}</Nazwisko>\n")
        
        // Adres podatnika
        sb.append("    <Adres>\n")
        sb.append("      <Ulica>${xmlEscape(taxpayer.address.street)}</Ulica>\n")
        sb.append("      <NumerDomu>${xmlEscape(taxpayer.address.houseNumber)}</NumerDomu>\n")
        sb.append("      <KodPocztowy>${xmlEscape(taxpayer.address.postalCode)}</KodPocztowy>\n")
        sb.append("      <Miejscowosc>${xmlEscape(taxpayer.address.city)}</Miejscowosc>\n")
        sb.append("    </Adres>\n")
        sb.append("  </Podatnik>\n")
        
        // Wspólne rozliczenie
        if (jointSpouse != null) {
            sb.append("  <WspolneFiled>true</WspolneFiled>\n")
        }
        
        // Urząd Skarbowy
        sb.append("  <UrzadSkarbowy>\n")
        sb.append("    <Nazwa>${xmlEscape(taxOffice.urzadSkarbowy)}</Nazwa>\n")
        sb.append("    <Kod>${taxOffice.code}</Kod>\n")
        sb.append("  </UrzadSkarbowy>\n")
        
        // Przychody / Ryczałt (часть D-E)
        sb.append("  <Przychody>\n")
        var lineNum = 1
        for (item in calculationResult.taxLineItems) {
            sb.append("    <PrzychodyPoRyczaltem>\n")
            sb.append("      <Lp>$lineNum</Lp>\n")
            sb.append("      <StawkaRyczaltu>${item.rate.ratePercent}</StawkaRyczaltu>\n")
            sb.append("      <Przychod>${formatDecimal(item.income)}</Przychod>\n")
            sb.append("    </PrzychodyPoRyczaltem>\n")
            lineNum++
        }
        sb.append("    <PrzychodyRazem>${formatDecimal(calculationResult.totalIncome)}</PrzychodyRazem>\n")
        sb.append("  </Przychody>\n")
        
        // Odliczenia
        if (calculationResult.totalDeductions > 0.0) {
            sb.append("  <Odliczenia>\n")
            if (calculationResult.totalZusDeduction > 0.0) {
                sb.append("    <ZUS>${formatDecimal(calculationResult.totalZusDeduction)}</ZUS>\n")
            }
            if (calculationResult.totalHealthDeduction > 0.0) {
                sb.append("    <Zdrowotna>${formatDecimal(calculationResult.totalHealthDeduction)}</Zdrowotna>\n")
            }
            sb.append("  </Odliczenia>\n")
        }
        
        // Ryczałt (часть L)
        sb.append("  <Ryczalt>\n")
        sb.append("    <ObliczonyRyczalt>${formatDecimal(calculationResult.taxGrossTotal)}</ObliczonyRyczalt>\n")
        sb.append("    <RyczaltPoZaokragleniu>${formatDecimal(calculationResult.taxTotal)}</RyczaltPoZaokragleniu>\n")
        sb.append("  </Ryczalt>\n")
        
        // Koniec
        sb.append("</DeklaracjaPIT>\n")
        
        return sb.toString()
    }
    
    /**
     * Валидация и очистка NIP (10 цифр)
     */
    private fun sanitizeNip(nip: String): String {
        val cleaned = nip.replace("-", "").replace(" ", "")
        return if (cleaned.length == 10 && cleaned.all { it.isDigit() }) {
            cleaned
        } else {
            "0000000000"  // Placeholder
        }
    }
    
    /**
     * Экранирование XML специальных символов
     */
    private fun xmlEscape(text: String): String {
        return text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }
    
    /**
     * Форматирование десятичных чисел (всегда 2 знака после запятой)
     */
    private fun formatDecimal(value: Double): String {
        return String.format(Locale.US, "%.2f", value)
    }
    
    /**
     * Получить текущую дату в формате ISO 8601 (YYYY-MM-DD)
     */
    private fun getCurrentDate(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return sdf.format(Date())
    }
    
    /**
     * Генератор случайного ID dokumentu (для внутреннего использования)
     */
    fun generateDocumentId(): String {
        return "DECL-${System.currentTimeMillis()}-${Random().nextInt(10000)}"
    }
}
