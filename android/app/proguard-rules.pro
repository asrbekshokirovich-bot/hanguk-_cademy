# Flutter's engine reaches these through JNI, so R8 cannot see the references
# and would strip them. The failure is at runtime, in a release build only.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# The engine ships code for Play's deferred-components feature, which this app
# does not use — so the Play Core library is not on the classpath and R8 stops
# with "Missing class com.google.android.play.core...". Those classes are only
# touched if deferred components are actually requested, which never happens
# here, so warning about them is noise that fails the build.
-dontwarn com.google.android.play.core.**
