#!/usr/bin/env bash
set -e
APP_NAME_XML=$(python3 -c 'import os; from xml.sax.saxutils import escape; print(escape(os.environ["APP_NAME"]))')
WEBSITE_JAVA=$(python3 -c 'import os,json; print(json.dumps(os.environ["WEBSITE_URL"])[1:-1])')
UPDATE_JAVA=$(python3 -c 'import os,json; print(json.dumps(os.environ.get("UPDATE_URL", ""))[1:-1])')
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
plugins { id 'com.android.application' version '8.10.1' apply false }
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx3g
android.useAndroidX=true
EOF

cat > app/build.gradle <<EOF
plugins { id 'com.android.application' }
def signingData = new groovy.json.JsonSlurper().parse(rootProject.file('signing.json'))
android {
    namespace '$PACKAGE_NAME'
    compileSdk 36
    defaultConfig {
        applicationId "$PACKAGE_NAME"
        minSdk 23
        targetSdk 36
        versionCode $VERSION_CODE
        versionName "$VERSION"
    }
    signingConfigs {
        release {
            storeFile file("../release.keystore")
            storePassword signingData.password
            keyAlias "appmaker"
            keyPassword signingData.password
        }
    }
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt')
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
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:usesCleartextTraffic="false"
        android:theme="@style/AppTheme">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
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
<resources><string name="app_name">$APP_NAME_XML</string></resources>
EOF

cat > app/src/main/res/values/colors.xml <<EOF
<resources>
    <color name="primary">$PRIMARY_COLOR</color>
    <color name="secondary">${SECONDARY_COLOR:-$PRIMARY_COLOR}</color>
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
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.os.Message;
import android.app.Dialog;
import android.content.ActivityNotFoundException;
import android.app.AlertDialog;
import android.widget.ImageView;
import android.widget.FrameLayout;
import org.json.JSONObject;
import java.net.URL;
import java.net.HttpURLConnection;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

public class MainActivity extends AppCompatActivity {
    private WebView webView;
    private SwipeRefreshLayout refreshLayout;
    private static final String START_URL = "$WEBSITE_JAVA";
    private static final boolean OPEN_EXTERNAL = $OPT_EXTERNAL;
    private static final boolean BACK_NAV = $OPT_BACK;
    private static final boolean PULL_REFRESH = $OPT_REFRESH;
    private static final String UPDATE_URL = "$UPDATE_JAVA";
    private ImageView splash;
    private WebView loginWindow;
    private Dialog loginDialog;
    private long lastUpdateCheck;
    private boolean updateChecking;

    private boolean sameSite(Uri uri) {
        Uri start = Uri.parse(START_URL);
        return "https".equalsIgnoreCase(uri.getScheme()) && start.getHost() != null && start.getHost().equalsIgnoreCase(uri.getHost());
    }
    private boolean navigateLink(Uri uri, boolean gesture) {
        String scheme = uri.getScheme();
        if ("https".equalsIgnoreCase(scheme)) {
            // Redirects remain in the same cookie/session context after first-party login.
            if (sameSite(uri) || !gesture || !OPEN_EXTERNAL) return false;
        } else if (!"mailto".equalsIgnoreCase(scheme) && !"tel".equalsIgnoreCase(scheme)) {
            return true;
        }
        try { CookieManager.getInstance().flush(); startActivity(new Intent(Intent.ACTION_VIEW, uri)); }
        catch (ActivityNotFoundException ignored) { }
        return true;
    }
    private void closeLoginWindow() {
        if (loginWindow != null) { loginWindow.stopLoading(); loginWindow.destroy(); loginWindow = null; }
        if (loginDialog != null) { loginDialog.dismiss(); loginDialog = null; }
        CookieManager.getInstance().flush();
    }
    private static byte[] readResponse(java.io.InputStream input) throws java.io.IOException {
        java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream(); byte[] buffer = new byte[4096]; int count;
        while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count); input.close(); return output.toByteArray();
    }
    private void checkUpdate() {
        if (UPDATE_URL.isEmpty() || updateChecking || (lastUpdateCheck > 0 && android.os.SystemClock.elapsedRealtime() - lastUpdateCheck < 300000)) return;
        updateChecking = true; lastUpdateCheck = android.os.SystemClock.elapsedRealtime();
        new Thread(() -> {
            try {
                HttpURLConnection connection = (HttpURLConnection) new URL(UPDATE_URL + "&installed=$VERSION_CODE").openConnection();
                connection.setConnectTimeout(10000); connection.setReadTimeout(10000);
                JSONObject update = new JSONObject(new String(readResponse(connection.getInputStream()), java.nio.charset.StandardCharsets.UTF_8));
                connection.disconnect();
                if (!getPackageName().equals(update.optString("package_name"))) return;
                if (update.optInt("version_code") <= $VERSION_CODE) return;
                String link = update.optString("url");
                if (!link.startsWith("https://")) return;
                runOnUiThread(() -> { if (isFinishing() || isDestroyed()) return; new AlertDialog.Builder(this).setTitle("Mise à jour disponible")
                    .setMessage("Une nouvelle version de votre application est prête.")
                    .setNegativeButton("Plus tard", null).setPositiveButton("Mettre à jour", (dialog, which) -> {
                        String installer = getPackageManager().getInstallerPackageName(getPackageName());
                        Uri target = Uri.parse("com.android.vending".equals(installer) ? "https://play.google.com/store/apps/details?id=" + getPackageName() : link);
                        startActivity(new Intent(Intent.ACTION_VIEW, target));
                    }).show(); });
            } catch (Exception ignored) { } finally { updateChecking = false; }
        }).start();
    }

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("$BACKGROUND_COLOR"));
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false);
        webView.getSettings().setSupportMultipleWindows(true);
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onCreateWindow(WebView view, boolean dialog, boolean userGesture, Message message) {
                if (!userGesture || loginWindow != null) return false;
                loginWindow = new WebView(MainActivity.this);
                loginWindow.getSettings().setJavaScriptEnabled(true);
                loginWindow.getSettings().setDomStorageEnabled(true);
                CookieManager.getInstance().setAcceptThirdPartyCookies(loginWindow, false);
                loginWindow.setWebViewClient(new WebViewClient() {
                    @Override public boolean shouldOverrideUrlLoading(WebView child, WebResourceRequest request) {
                        Uri uri = request.getUrl();
                        return !"https".equalsIgnoreCase(uri.getScheme());
                    }
                });
                loginWindow.setWebChromeClient(new WebChromeClient() {
                    @Override public void onCloseWindow(WebView window) { closeLoginWindow(); }
                });
                loginDialog = new Dialog(MainActivity.this);
                loginDialog.setContentView(loginWindow);
                loginDialog.setOnCancelListener(d -> closeLoginWindow());
                loginDialog.show();
                if (loginDialog.getWindow() != null) loginDialog.getWindow().setLayout(-1, -1);
                ((WebView.WebViewTransport) message.obj).setWebView(loginWindow); message.sendToTarget(); return true;
            }
        });
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                return navigateLink(uri, request.hasGesture());
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                if (refreshLayout != null) refreshLayout.setRefreshing(false);
                if (splash != null) splash.setVisibility(android.view.View.GONE);
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

        if (${OPT_SPLASH:-true}) {
            android.view.View content = PULL_REFRESH ? refreshLayout : webView;
            ((android.view.ViewGroup) content.getParent()).removeView(content);
            FrameLayout frame = new FrameLayout(this); frame.addView(content);
            splash = new ImageView(this); splash.setImageResource(getApplicationInfo().icon);
            splash.setBackgroundColor(Color.parseColor("$BACKGROUND_COLOR")); splash.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
            frame.addView(splash, new FrameLayout.LayoutParams(-1, -1)); setContentView(frame);
            splash.postDelayed(() -> splash.setVisibility(android.view.View.GONE), 2500);
        }
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content), (view, insets) -> {
            androidx.core.graphics.Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom); return insets;
        });
        if (savedInstanceState == null || webView.restoreState(savedInstanceState) == null) webView.loadUrl(START_URL);
    }

    @Override protected void onResume() {
        super.onResume(); if (webView != null) webView.onResume(); checkUpdate();
    }
    @Override protected void onPause() {
        CookieManager.getInstance().flush(); if (webView != null) webView.onPause(); super.onPause();
    }
    @Override protected void onSaveInstanceState(Bundle state) {
        if (webView != null) webView.saveState(state); super.onSaveInstanceState(state);
    }
    @Override protected void onDestroy() {
        closeLoginWindow();
        if (webView != null) {
            webView.stopLoading();
            if (webView.getParent() instanceof android.view.ViewGroup) ((android.view.ViewGroup) webView.getParent()).removeView(webView);
            webView.destroy(); webView = null;
        }
        super.onDestroy();
    }
    @Override
    public void onBackPressed() {
        if (loginWindow != null) { if (loginWindow.canGoBack()) loginWindow.goBack(); else closeLoginWindow(); return; }
        if (BACK_NAV && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
EOF

if [ -n "$ICON_URL" ]; then
  curl --fail -sL "$ICON_URL" -o /tmp/icon.png
  identify /tmp/icon.png >/dev/null
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

