@echo off
setlocal
cd /d "%~dp0"
where flutter >nul 2>&1
if errorlevel 1 (
 echo ERROR: Flutter not found in PATH. Install Flutter and Android Studio first.
 pause
 exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_android.ps1"
if errorlevel 1 (
 echo Build failed. See error details above.
 pause
 exit /b 1
)
echo.
echo SUCCESS: APK in dist\Receiptly-v1.0.0.apk
pause
