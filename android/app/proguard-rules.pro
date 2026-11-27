# Preserve Gson generic signatures and flutter_local_notifications models/receivers under R8 full mode
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.io.Serializable {
    *;
}
