# ML Kit text recognition: only the Latin script model is bundled; the plugin
# still references the optional Chinese/Devanagari/Japanese/Korean ones.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Health Connect / home_widget / notifications use reflection on these.
-keep class androidx.health.** { *; }
-keep class es.antonborri.home_widget.** { *; }
-keep class com.dexterous.** { *; }
