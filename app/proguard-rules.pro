# ВАЖНО: включение minifyEnabled требует тщательного тестирования release-сборки перед публикацией —
# особенно экспорт отчётов (Apache POI активно использует рефлексию) и Room (генерируемый код).
# Соберите release APK, установите на реальное устройство и пройдите все сценарии (добавление
# записей, экспорт годового отчёта, покупка/восстановление Pro, показ рекламы) до релиза в Play.

# Room — сгенерированный код доступа к базе
-keep class androidx.room.** { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }
-dontwarn androidx.room.paging.**

# Apache POI (генерация xlsx-отчётов) — использует рефлексию и XML-парсинг, легко ломается R8
-keep class org.apache.poi.** { *; }
-keep class org.apache.xmlbeans.** { *; }
-keep class org.openxmlformats.** { *; }
-keep class schemasMicrosoftComVml.** { *; }
-dontwarn org.apache.poi.**
-dontwarn org.apache.xmlbeans.**
-dontwarn org.openxmlformats.**
-dontwarn org.apache.commons.compress.**
-dontwarn javax.xml.**
-dontwarn org.w3c.dom.**

# Google Play Billing — публичные модели покупок (Purchase, ProductDetails и т.п.)
-keep class com.android.billingclient.api.** { *; }

# Google Mobile Ads / UMP
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }
-dontwarn com.google.android.gms.ads.**

# Наши модели данных (Entry и т.п.) — не переименовывать поля/классы, используемые Room/Gson-подобной сериализацией
-keep class com.example.fa_ksiegowy.Entry { *; }

# Kotlin coroutines / metadata
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod, RuntimeVisibleAnnotations
-dontwarn kotlinx.coroutines.**

# log4j / bnd / osgi / findbugs — опциональные транзитивные зависимости Apache POI,
# используются только в desktop/OSGi-окружениях и на Android никогда не вызываются.
-dontwarn aQute.bnd.annotation.**
-dontwarn edu.umd.cs.findbugs.annotations.**
-dontwarn org.osgi.framework.**
-dontwarn org.apache.logging.log4j.**
-dontwarn java.awt.**

# pdfbox-android — опциональный JPEG2000-кодек (gemalto), не используется без явного
# добавления соответствующей нативной библиотеки.
-dontwarn com.gemalto.jp2.**

# play-services-ads ссылается на API из более новых версий Android SDK, которых нет
# на текущем compileSdk; на рантайме код просто не выполнится на старых устройствах.
-dontwarn android.media.LoudnessCodecController**
