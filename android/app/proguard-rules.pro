# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.kts.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line numbers, uncomment this to hide the original
# source file name.
#-renamesourcefileattribute SourceFile

# Google Play Core (for deferred components)
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.firestore.** { *; }
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.firebase.storage.** { *; }

# SQLite (sqflite)
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }

# Camera (mobile_scanner)
-keep class com.github.yuriy-budiyev.code_scanner.** { *; }
-keep class com.journeyapps.barcodescanner.** { *; }

# Bluetooth (flutter_blue_plus)
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.polidea.rxandroidble2.** { *; }

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Shared Preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Path Provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Print Bluetooth Thermal
-keep class com.example.print_bluetooth_thermal.** { *; }

# Share Plus
-keep class io.flutter.plugins.share.** { *; }

# URL Launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep data for analytics
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

# Keep all classes that might be used in reflection
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep all classes in packages that are used by Flutter plugins
-keep class * extends io.flutter.embedding.engine.FlutterEngine { *; }
-keep class * extends io.flutter.plugin.common.PluginRegistry { *; }