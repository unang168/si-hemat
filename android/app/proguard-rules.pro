# Preserve Gson generic signatures and flutter_local_notifications models/receivers under R8 full mode
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.io.Serializable {
    *;
}

# Preserve PDFBox-Android security handlers, decryption & rendering classes (without bloating R8 with unused BouncyCastle packages)
-keep class com.tom_roush.pdfbox.pdmodel.encryption.** { *; }
-keep class com.tom_roush.pdfbox.rendering.** { *; }
-keep class com.tom_roush.pdfbox.android.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
-keep class org.bouncycastle.jce.provider.BouncyCastleProvider { *; }
-keep class org.bouncycastle.jcajce.provider.symmetric.AES** { *; }
-keep class org.bouncycastle.jcajce.provider.symmetric.ARC4** { *; }
-keep class org.bouncycastle.jcajce.provider.digest.MD5** { *; }
-keep class org.bouncycastle.jcajce.provider.digest.SHA1** { *; }
-keep class org.bouncycastle.jcajce.provider.digest.SHA256** { *; }
-keep class org.bouncycastle.jcajce.provider.digest.SHA384** { *; }
-keep class org.bouncycastle.jcajce.provider.digest.SHA512** { *; }
-dontwarn com.tom_roush.pdfbox.**
-dontwarn com.tom_roush.fontbox.**
-dontwarn org.bouncycastle.**
-dontwarn org.spongycastle.**
-dontwarn com.gemalto.jp2.**
-dontwarn java.awt.**
-dontwarn javax.imageio.**
