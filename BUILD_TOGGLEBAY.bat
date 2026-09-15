@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title ToggleBay Builder

echo ============================================================
echo ToggleBay Builder
echo Builds the debug APK and/or release AAB from this source tree.
echo ============================================================
echo.

rem ---- Java 17 -------------------------------------------------
where java >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Java was not found on PATH.
  echo Install JDK 17, reopen this window, and run this BAT again.
  goto :fail
)

echo [OK] Java found:
java -version
echo.

rem ---- Android SDK ----------------------------------------------
if not defined ANDROID_HOME if defined ANDROID_SDK_ROOT set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
if not defined ANDROID_HOME if exist "%LOCALAPPDATA%\Android\Sdk" set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
if not defined ANDROID_HOME (
  echo [ERROR] Android SDK not found.
  echo Set ANDROID_HOME or ANDROID_SDK_ROOT, or install Android Studio.
  goto :fail
)
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
echo [OK] Android SDK: %ANDROID_HOME%

rem ---- Ensure API 36 platform when sdkmanager is available -------
set "SDKMANAGER="
if exist "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" set "SDKMANAGER=%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat"
if not defined SDKMANAGER if exist "%ANDROID_HOME%\tools\bin\sdkmanager.bat" set "SDKMANAGER=%ANDROID_HOME%\tools\bin\sdkmanager.bat"

if not exist "%ANDROID_HOME%\platforms\android-36\android.jar" (
  if defined SDKMANAGER (
    echo [INFO] Android API 36 is missing. Installing required SDK packages...
    call "%SDKMANAGER%" "platforms;android-36" "build-tools;35.0.0"
    if errorlevel 1 goto :fail
  ) else (
    echo [ERROR] Android API 36 is missing and sdkmanager.bat was not found.
    echo Install Android SDK Platform 36 in Android Studio, then rerun this BAT.
    goto :fail
  )
)

rem ---- Gradle 8.13 ----------------------------------------------
set "GRADLE_EXE="
where gradle >nul 2>nul
if not errorlevel 1 set "GRADLE_EXE=gradle"

if not defined GRADLE_EXE (
  set "TOOLS_DIR=%CD%\.togglebay-tools"
  set "GRADLE_HOME_LOCAL=!TOOLS_DIR!\gradle-8.13"
  set "GRADLE_ZIP=!TOOLS_DIR!\gradle-8.13-bin.zip"
  if not exist "!GRADLE_HOME_LOCAL!\bin\gradle.bat" (
    echo [INFO] Gradle 8.13 not found. Bootstrapping a local copy...
    if not exist "!TOOLS_DIR!" mkdir "!TOOLS_DIR!"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing 'https://services.gradle.org/distributions/gradle-8.13-bin.zip' -OutFile '!GRADLE_ZIP!'"
    if errorlevel 1 goto :fail
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '!GRADLE_ZIP!' -DestinationPath '!TOOLS_DIR!' -Force"
    if errorlevel 1 goto :fail
  )
  set "GRADLE_EXE=!GRADLE_HOME_LOCAL!\bin\gradle.bat"
)

echo [OK] Gradle: %GRADLE_EXE%
echo.

echo What do you want to build?
echo   1. Debug APK
echo   2. Release AAB
echo   3. Both ^(recommended^)
set /p "CHOICE=Choose 1, 2, or 3 [3]: "
if "%CHOICE%"=="" set "CHOICE=3"

if "%CHOICE%"=="1" goto :debug
if "%CHOICE%"=="2" goto :release
if "%CHOICE%"=="3" goto :both
echo [ERROR] Invalid choice.
goto :fail

:debug
echo.
echo [BUILD] Debug APK...
call "%GRADLE_EXE%" --no-daemon --stacktrace clean assembleDebug
if errorlevel 1 goto :fail
goto :collect

:release
echo.
echo [BUILD] Release AAB...
call "%GRADLE_EXE%" --no-daemon --stacktrace clean bundleRelease
if errorlevel 1 goto :fail
goto :collect

:both
echo.
echo [BUILD] Debug APK + Release AAB...
call "%GRADLE_EXE%" --no-daemon --stacktrace clean assembleDebug bundleRelease
if errorlevel 1 goto :fail
goto :collect

:collect
if not exist "dist" mkdir "dist"

set "APK=build\outputs\apk\debug\PowerToggles-debug.apk"
set "AAB=build\outputs\bundle\release\PowerToggles-release.aab"

if exist "%APK%" copy /Y "%APK%" "dist\ToggleBay-debug.apk" >nul
if exist "%AAB%" copy /Y "%AAB%" "dist\ToggleBay-release.aab" >nul

echo.
echo ============================================================
echo BUILD COMPLETE
echo ============================================================
if exist "dist\ToggleBay-debug.apk" echo Debug APK:  %CD%\dist\ToggleBay-debug.apk
if exist "dist\ToggleBay-release.aab" echo Release AAB: %CD%\dist\ToggleBay-release.aab
echo.
echo NOTE: BUILD_TOGGLEBAY.bat does NOT create or store signing keys.
echo The release AAB is the technical release bundle; Play upload signing
echo remains a separate release step when signing/account setup is authorized.
echo.
explorer "%CD%\dist" >nul 2>nul
pause
exit /b 0

:fail
echo.
echo ============================================================
echo BUILD FAILED
echo ============================================================
echo Read the error above, fix the missing prerequisite, and rerun.
echo.
pause
exit /b 1
