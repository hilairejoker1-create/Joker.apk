#!/usr/bin/env bash
set -e
PKG_PATH=$(echo "$PACKAGE_NAME" | tr '.' '/')
mkdir -p app/src/main/java/$PKG_PATH
mkdir -p app/src/main/res/values app/src/main/res/mipmap-xxxhdpi app/src/main/res/drawable

cat > settings.gradle <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "app"
include ":app"
EOF

cat > build.gradle <<'EOF'
plugins { id 'com.android.application' version '8.5.2' apply false }
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx3g
android.useAndroidX=true
EOF

cat > app/build.gradle <<EOF
plugins { id 'com.android.application' }
android {
    namespace '$PACKAGE_NAME'
    compileSdk 34
    defaultConfig {
        applicationId "$PACKAGE_NAME"
        minSdk 23
        targetSdk 34
        versionCode $VERSION_CODE
        versionName "$VERSION"
    }
    signingConfigs {
        release {
            storeFile file("../release.keystore")
            storePassword "appmakerayiti"
            keyAlias "appmaker"
            keyPassword "appmakerayiti"
        }
    }
    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
dependencies {
    implementation platform('org.jetbrains.kotlin:kotlin-bom:1.8.22')
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'androidx.swiperefreshlayout:swiperefreshlayout:1.1.0'
}
EOF

cat > app/src/main/AndroidManifest.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:usesCleartextTraffic="true"
        android:theme="@style/AppTheme">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="$ORIENTATION"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > app/src/main/res/values/strings.xml <<EOF
<resources><string name="app_name">$APP_NAME</string></resources>
EOF

cat > app/src/main/res/values/colors.xml <<EOF
<resources>
    <color name="primary">$PRIMARY_COLOR</color>
    <color name="background">$BACKGROUND_COLOR</color>
</resources>
EOF

if [ "$OPT_FULLSCREEN" = "true" ]; then
  EXTRA_THEME='<item name="android:windowFullscreen">true</item>'
else
  EXTRA_THEME=''
fi

cat > app/src/main/res/values/themes.xml <<EOF
<resources>
    <style name="AppTheme" parent="Theme.AppCompat.Light.NoActionBar">
        <item name="android:statusBarColor">@color/primary</item>
        <item name="android:windowBackground">@color/background</item>
        $EXTRA_THEME
    </style>
</resources>
EOF

cat > app/src/main/java/$PKG_PATH/MainActivity.java <<EOF
package $PACKAGE_NAME;

import android.annotation.SuppressLint;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import androidx.appcompat.app.AppCompatActivity;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

public class MainActivity extends AppCompatActivity {
    private WebView webView;
    private SwipeRefreshLayout refreshLayout;
    private static final String START_URL = "$WEBSITE_URL";
    private static final boolean OPEN_EXTERNAL = $OPT_EXTERNAL;
    private static final boolean BACK_NAV = $OPT_BACK;
    private static final boolean PULL_REFRESH = $OPT_REFRESH;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("$BACKGROUND_COLOR"));
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String host = Uri.parse(START_URL).getHost();
                if (OPEN_EXTERNAL && host != null && uri.getHost() != null && !uri.getHost().contains(host)) {
                    startActivity(new Intent(Intent.ACTION_VIEW, uri));
                    return true;
                }
                return false;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                if (refreshLayout != null) refreshLayout.setRefreshing(false);
            }
        });

        if (PULL_REFRESH) {
            refreshLayout = new SwipeRefreshLayout(this);
            refreshLayout.addView(webView);
            refreshLayout.setOnRefreshListener(new SwipeRefreshLayout.OnRefreshListener() {
                @Override public void onRefresh() { webView.reload(); }
            });
            setContentView(refreshLayout);
        } else {
            setContentView(webView);
        }

        webView.loadUrl(START_URL);
    }

    @Override
    public void onBackPressed() {
        if (BACK_NAV && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
EOF

if [ -n "$ICON_URL" ]; then
  curl -sL "$ICON_URL" -o /tmp/icon.png || true
fi
if [ ! -s /tmp/icon.png ]; then
  convert -size 512x512 xc:"$PRIMARY_COLOR" /tmp/icon.png
fi
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  name=${d%%:*}; size=${d##*:}
  mkdir -p app/src/main/res/mipmap-$name
  convert /tmp/icon.png -resize ${size}x${size}^ -gravity center -extent ${size}x${size} \
    app/src/main/res/mipmap-$name/ic_launcher.png
done

