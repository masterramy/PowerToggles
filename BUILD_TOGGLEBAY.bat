@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title ToggleBay Builder

echo ============================================================
echo ToggleBay Builder
echo Builds the debug APK and/or release AAB from this source tree.
echo Uses pinned local JDK 17 + Gradle 8.13 for reproducibility.
echo ============================================================
echo.

rem ---- Tool cache ------------------------------------------------
set "TOOLS_DIR=%CD%\.togglebay-tools"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"

rem ---- Pin JDK 17 -------------------------------------------------
set "JDK_ARCH=x64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "JDK_ARCH=aarch64"
set "JDK_HOME_LOCAL=%TOOLS_DIR%\jdk-17"
set "JDK_ZIP=%TOOLS_DIR%\temurin17.zip"
set "JDK_STAGE=%TOOLS_DIR%\jdk17-stage"

if not exist "%JDK_HOME_LOCAL%\bin\java.exe" (
  echo [INFO] Pinned JDK 17 not found. Bootstrapping Eclipse Temurin 17...
  if exist "%JDK_STAGE%" rmdir /S /Q "%JDK_STAGE%"
  if exist "%JDK_ZIP%" del /Q "%JDK_ZIP%"
  mkdir "%JDK_STAGE%"

  set "TB_JDK_URL=https://api.adoptium.net/v3/binary/latest/17/ga/windows/%JDK_ARCH%/jdk/hotspot/normal/eclipse"
  set "TB_JDK_ZIP=%JDK_ZIP%"
  set "TB_JDK_STAGE=%JDK_STAGE%"
  set "TB_JDK_HOME=%JDK_HOME_LOCAL%"

  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $env:TB_JDK_URL -OutFile $env:TB_JDK_ZIP; Expand-Archive -LiteralPath $env:TB_JDK_ZIP -DestinationPath $env:TB_JDK_STAGE -Force; $jdk = Get-ChildItem -Path $env:TB_JDK_STAGE -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } | Select-Object -First 1; if (-not $jdk) { throw 'Downloaded JDK archive did not contain bin\java.exe' }; if (Test-Path $env:TB_JDK_HOME) { Remove-Item -Recurse -Force $env:TB_JDK_HOME }; Move-Item -LiteralPath $jdk.FullName -Destination $env:TB_JDK_HOME"
  if errorlevel 1 goto :fail
  if exist "%JDK_STAGE%" rmdir /S /Q "%JDK_STAGE%"
  if exist "%JDK_ZIP%" del /Q "%JDK_ZIP%"
)

if not exist "%JDK_HOME_LOCAL%\bin\java.exe" (
  echo [ERROR] Pinned JDK 17 bootstrap did not produce java.exe.
  goto :fail
)

set "JAVA_HOME=%JDK_HOME_LOCAL%"
set "PATH=%JAVA_HOME%\bin;%PATH%"

rem Remove outside JVM hooks that can override or contaminate this build.
set "JAVA_OPTS="
set "JAVA_TOOL_OPTIONS="
set "_JAVA_OPTIONS="
set "JDK_JAVA_OPTIONS="
set "GRADLE_OPTS="

"%JAVA_HOME%\bin\java.exe" -XshowSettings:properties -version 2>&1 | findstr /C:"java.specification.version = 17" >nul
if errorlevel 1 (
  echo [ERROR] Builder Java is not JDK 17. Refusing to continue.
  "%JAVA_HOME%\bin\java.exe" -version
  goto :fail
)

echo [OK] Builder Java pinned to:
"%JAVA_HOME%\bin\java.exe" -version
echo.

rem ---- Android SDK -----------------------------------------------
if not defined ANDROID_HOME if defined ANDROID_SDK_ROOT set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
if not defined ANDROID_HOME if exist "%LOCALAPPDATA%\Android\Sdk" set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
if not defined ANDROID_HOME (
  echo [ERROR] Android SDK not found.
  echo Install Android Studio, or set ANDROID_HOME / ANDROID_SDK_ROOT.
  goto :fail
)
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
echo [OK] Android SDK: %ANDROID_HOME%

set "SDKMANAGER="
if exist "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" set "SDKMANAGER=%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat"
if not defined SDKMANAGER if exist "%ANDROID_HOME%\tools\bin\sdkmanager.bat" set "SDKMANAGER=%ANDROID_HOME%\tools\bin\sdkmanager.bat"

if not exist "%ANDROID_HOME%\platforms\android-36\android.jar" (
  if defined SDKMANAGER (
    echo [INFO] Android API 36 missing. Installing required SDK packages...
    call "%SDKMANAGER%" "platforms;android-36" "build-tools;35.0.0"
    if errorlevel 1 goto :fail
  ) else (
    echo [ERROR] Android API 36 missing and sdkmanager.bat was not found.
    echo Install Android SDK Platform 36 in Android Studio, then rerun.
    goto :fail
  )
)

if not exist "%ANDROID_HOME%\build-tools\35.0.0" (
  if defined SDKMANAGER (
    echo [INFO] Android Build Tools 35.0.0 missing. Installing...
    call "%SDKMANAGER%" "build-tools;35.0.0"
    if errorlevel 1 goto :fail
  ) else (
    echo [ERROR] Android Build Tools 35.0.0 missing and sdkmanager.bat was not found.
    goto :fail
  )
)

rem ---- Pin Gradle 8.13 -------------------------------------------
set "GRADLE_HOME_LOCAL=%TOOLS_DIR%\gradle-8.13"
set "GRADLE_ZIP=%TOOLS_DIR%\gradle-8.13-bin.zip"
if not exist "%GRADLE_HOME_LOCAL%\bin\gradle.bat" (
  echo [INFO] Pinned Gradle 8.13 not found. Bootstrapping local copy...
  if exist "%GRADLE_ZIP%" del /Q "%GRADLE_ZIP%"
  set "TB_GRADLE_ZIP=%GRADLE_ZIP%"
  set "TB_TOOLS_DIR=%TOOLS_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing 'https://services.gradle.org/distributions/gradle-8.13-bin.zip' -OutFile $env:TB_GRADLE_ZIP; Expand-Archive -LiteralPath $env:TB_GRADLE_ZIP -DestinationPath $env:TB_TOOLS_DIR -Force"
  if errorlevel 1 goto :fail
  if exist "%GRADLE_ZIP%" del /Q "%GRADLE_ZIP%"
)

if not exist "%GRADLE_HOME_LOCAL%\bin\gradle.bat" (
  echo [ERROR] Gradle 8.13 bootstrap failed.
  goto :fail
)
set "GRADLE_EXE=%GRADLE_HOME_LOCAL%\bin\gradle.bat"

rem Isolate Gradle from any Java-25 daemon/cache state on the host machine.
set "GRADLE_USER_HOME=%TOOLS_DIR%\gradle-user-home-jdk17"
if not exist "%GRADLE_USER_HOME%" mkdir "%GRADLE_USER_HOME%"
if exist "%CD%\.gradle" rmdir /S /Q "%CD%\.gradle"

set "GRADLE_VERSION_FILE=%TOOLS_DIR%\gradle-version.txt"
call "%GRADLE_EXE%" --no-daemon --version > "%GRADLE_VERSION_FILE%" 2>&1
if errorlevel 1 (
  type "%GRADLE_VERSION_FILE%"
  echo [ERROR] Gradle could not start under the pinned JDK 17.
  goto :fail
)
type "%GRADLE_VERSION_FILE%"
findstr /R /C:"Gradle 8\.13" "%GRADLE_VERSION_FILE%" >nul
if errorlevel 1 (
  echo [ERROR] Unexpected Gradle version. Expected 8.13.
  goto :fail
)
findstr /R /C:"JVM:.*17\." "%GRADLE_VERSION_FILE%" >nul
if errorlevel 1 (
  echo [ERROR] Gradle is NOT running on JDK 17. Refusing to build.
  echo [ERROR] The JVM line above must show JVM: 17.x.
  goto :fail
)
echo [OK] Gradle 8.13 is running on JDK 17.
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
if exist "dist\ToggleBay-debug.apk" echo Debug APK:   %CD%\dist\ToggleBay-debug.apk
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
