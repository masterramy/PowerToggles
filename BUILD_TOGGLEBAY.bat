@echo off
setlocal EnableExtensions DisableDelayedExpansion

pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Could not enter the ToggleBay source directory.
  exit /b 1
)

title ToggleBay Builder
set "BUILDER_VERSION=2026-09-18-r4"
set "EXPECTED_PACKAGE=com.ramybaheeg.togglebay"
set "EXPECTED_VERSION_CODE=1"
set "EXPECTED_VERSION_NAME=1.0.0"
set "EXPECTED_TARGET_SDK=36"
set "GRADLE_VERSION=8.13"
set "GRADLE_SHA256=20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78"
set "BUILD_TOOLS_VERSION=35.0.0"
set "TOOLS_DIR=%CD%\.togglebay-tools"
set "DIST_DIR=%CD%\dist"
set "LAST_ERROR=Unknown builder failure."
set "INTERACTIVE=0"
set "MODE="

echo ============================================================
echo ToggleBay Builder  %BUILDER_VERSION%
echo Builds the debug APK and/or technical release AAB.
echo Toolchain: verified JDK 17 + Gradle 8.13 + Android API 36.
echo ============================================================
echo.

call :require_project
if errorlevel 1 goto :fail
call :find_powershell
if errorlevel 1 goto :fail
call :ensure_dirs
if errorlevel 1 goto :fail
call :detect_arch
if errorlevel 1 goto :fail
call :ensure_jdk
if errorlevel 1 goto :fail
call :activate_jdk
if errorlevel 1 goto :fail
call :ensure_gradle
if errorlevel 1 goto :fail
call :verify_gradle
if errorlevel 1 goto :fail
call :find_android_sdk
if errorlevel 1 goto :fail
call :ensure_android_packages
if errorlevel 1 goto :fail
call :resolve_mode "%~1"
if errorlevel 1 goto :fail
call :clear_outputs
if errorlevel 1 goto :fail
call :run_build
if errorlevel 1 goto :fail
call :collect_and_verify
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo BUILD VERIFIED SUCCESSFULLY
echo ============================================================
if exist "%DIST_DIR%\ToggleBay-debug.apk" echo Debug APK:   "%DIST_DIR%\ToggleBay-debug.apk"
if exist "%DIST_DIR%\ToggleBay-release.aab" echo Release AAB: "%DIST_DIR%\ToggleBay-release.aab"
echo Build record: "%DIST_DIR%\BUILD_INFO.txt"
echo.
echo NOTE: The release AAB is intentionally not signed with a private upload key.
echo Play upload signing remains a separate release step after account/signing authority clears.
echo.
if "%INTERACTIVE%"=="1" start "" "%DIST_DIR%" >nul 2>&1
if "%INTERACTIVE%"=="1" pause
popd
exit /b 0

:require_project
if not exist "build.gradle" (
  set "LAST_ERROR=build.gradle is missing. Extract the full project ZIP before running the builder."
  exit /b 1
)
if not exist "AndroidManifest.xml" (
  set "LAST_ERROR=AndroidManifest.xml is missing. This is not the full ToggleBay source tree."
  exit /b 1
)
if not exist "src" (
  set "LAST_ERROR=src directory is missing. This is not the full ToggleBay source tree."
  exit /b 1
)
if not exist "release-identity\res" (
  set "LAST_ERROR=release-identity resources are missing. Re-extract the full source ZIP."
  exit /b 1
)
exit /b 0

:find_powershell
where powershell.exe >nul 2>&1
if not errorlevel 1 (
  set "PS_EXE=powershell.exe"
  exit /b 0
)
where pwsh.exe >nul 2>&1
if not errorlevel 1 (
  set "PS_EXE=pwsh.exe"
  exit /b 0
)
set "LAST_ERROR=PowerShell was not found. Windows PowerShell or PowerShell 7 is required for verified tool downloads."
exit /b 1

:ensure_dirs
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%" >nul 2>&1
if not exist "%TOOLS_DIR%" (
  set "LAST_ERROR=Could not create the local tool cache: %TOOLS_DIR%"
  exit /b 1
)
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%" >nul 2>&1
if not exist "%DIST_DIR%" (
  set "LAST_ERROR=Could not create the output directory: %DIST_DIR%"
  exit /b 1
)
exit /b 0

:detect_arch
set "JDK_ARCH=x64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "JDK_ARCH=aarch64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "JDK_ARCH=aarch64"
exit /b 0

:ensure_jdk
set "JDK_HOME_LOCAL=%TOOLS_DIR%\jdk-17"
set "JDK_ZIP=%TOOLS_DIR%\temurin17.zip"
set "JDK_STAGE=%TOOLS_DIR%\jdk17-stage"
if exist "%JDK_HOME_LOCAL%\bin\java.exe" (
  call :check_jdk17
  if not errorlevel 1 exit /b 0
  echo [WARN] Cached JDK is invalid or not Java 17. Repairing it...
  rmdir /S /Q "%JDK_HOME_LOCAL%" >nul 2>&1
)

echo [INFO] Downloading a verified Eclipse Temurin JDK 17 for %JDK_ARCH%...
if exist "%JDK_STAGE%" rmdir /S /Q "%JDK_STAGE%" >nul 2>&1
if exist "%JDK_ZIP%" del /Q "%JDK_ZIP%" >nul 2>&1
mkdir "%JDK_STAGE%" >nul 2>&1
if not exist "%JDK_STAGE%" (
  set "LAST_ERROR=Could not create the JDK staging directory."
  exit /b 1
)

set "TB_JDK_ARCH=%JDK_ARCH%"
set "TB_JDK_META_URL=https://api.adoptium.net/v3/assets/feature_releases/17/ga?architecture=%JDK_ARCH%&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=windows&page=0&page_size=1&project=jdk&sort_method=DEFAULT&sort_order=DESC&vendor=eclipse"
set "TB_JDK_ZIP=%JDK_ZIP%"
set "TB_JDK_STAGE=%JDK_STAGE%"
set "TB_JDK_HOME=%JDK_HOME_LOCAL%"

"%PS_EXE%" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $meta=Invoke-RestMethod -Uri $env:TB_JDK_META_URL; $bin=$meta[0].binaries | Where-Object { $_.architecture -eq $env:TB_JDK_ARCH -and $_.image_type -eq 'jdk' -and $_.os -eq 'windows' } | Select-Object -First 1; if(-not $bin){throw 'Adoptium metadata returned no matching Windows JDK 17 binary.'}; $url=$bin.package.link; $expected=$bin.package.checksum.ToLowerInvariant(); $downloaded=$false; for($i=1;$i -le 3;$i++){try{Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $env:TB_JDK_ZIP; $downloaded=$true; break}catch{if($i -eq 3){throw}; Start-Sleep -Seconds (2*$i)}}; if(-not $downloaded){throw 'JDK download did not complete.'}; $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $env:TB_JDK_ZIP).Hash.ToLowerInvariant(); if($actual -ne $expected){throw ('JDK SHA-256 mismatch. Expected '+$expected+' got '+$actual)}; Add-Type -AssemblyName System.IO.Compression.FileSystem; $z=[IO.Compression.ZipFile]::OpenRead($env:TB_JDK_ZIP); $z.Dispose(); Expand-Archive -LiteralPath $env:TB_JDK_ZIP -DestinationPath $env:TB_JDK_STAGE -Force; $jdk=Get-ChildItem -Path $env:TB_JDK_STAGE -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } | Select-Object -First 1; if(-not $jdk){throw 'Verified JDK archive did not contain bin\java.exe.'}; if(Test-Path $env:TB_JDK_HOME){Remove-Item -Recurse -Force $env:TB_JDK_HOME}; Move-Item -LiteralPath $jdk.FullName -Destination $env:TB_JDK_HOME"
if errorlevel 1 (
  set "LAST_ERROR=Verified JDK 17 bootstrap failed. Check internet access and rerun; partial downloads are rejected."
  exit /b 1
)

if exist "%JDK_STAGE%" rmdir /S /Q "%JDK_STAGE%" >nul 2>&1
if exist "%JDK_ZIP%" del /Q "%JDK_ZIP%" >nul 2>&1
call :check_jdk17
if errorlevel 1 (
  set "LAST_ERROR=JDK 17 bootstrap completed but the resulting java.exe failed the Java 17 verification."
  exit /b 1
)
exit /b 0

:check_jdk17
if not exist "%JDK_HOME_LOCAL%\bin\java.exe" exit /b 1
"%JDK_HOME_LOCAL%\bin\java.exe" -XshowSettings:properties -version 2>&1 | findstr /C:"java.specification.version = 17" >nul
if errorlevel 1 exit /b 1
exit /b 0

:activate_jdk
set "JAVA_HOME=%JDK_HOME_LOCAL%"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "JAVA_OPTS="
set "JAVA_TOOL_OPTIONS="
set "_JAVA_OPTIONS="
set "JDK_JAVA_OPTIONS="
set "GRADLE_OPTS="
call :check_jdk17
if errorlevel 1 (
  set "LAST_ERROR=The builder failed to activate its private JDK 17 runtime."
  exit /b 1
)
echo [OK] Java runtime:
"%JAVA_HOME%\bin\java.exe" -version
exit /b 0

:ensure_gradle
set "GRADLE_HOME_LOCAL=%TOOLS_DIR%\gradle-%GRADLE_VERSION%"
set "GRADLE_ZIP=%TOOLS_DIR%\gradle-%GRADLE_VERSION%-bin.zip"
set "GRADLE_EXE=%GRADLE_HOME_LOCAL%\bin\gradle.bat"
set "GRADLE_VERSION_FILE=%TOOLS_DIR%\gradle-version.txt"
set "GRADLE_USER_HOME=%TOOLS_DIR%\gradle-user-home-jdk17"
if not exist "%GRADLE_USER_HOME%" mkdir "%GRADLE_USER_HOME%" >nul 2>&1

if exist "%GRADLE_EXE%" (
  call :probe_gradle
  if not errorlevel 1 exit /b 0
  echo [WARN] Cached Gradle is invalid or cannot run on JDK 17. Repairing it...
  rmdir /S /Q "%GRADLE_HOME_LOCAL%" >nul 2>&1
)

echo [INFO] Downloading verified Gradle %GRADLE_VERSION%...
if exist "%GRADLE_ZIP%" del /Q "%GRADLE_ZIP%" >nul 2>&1
set "TB_GRADLE_URL=https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip"
set "TB_GRADLE_ZIP=%GRADLE_ZIP%"
set "TB_GRADLE_SHA=%GRADLE_SHA256%"
set "TB_TOOLS_DIR=%TOOLS_DIR%"
set "TB_GRADLE_HOME=%GRADLE_HOME_LOCAL%"

"%PS_EXE%" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $downloaded=$false; for($i=1;$i -le 3;$i++){try{Invoke-WebRequest -UseBasicParsing -Uri $env:TB_GRADLE_URL -OutFile $env:TB_GRADLE_ZIP; $downloaded=$true; break}catch{if($i -eq 3){throw}; Start-Sleep -Seconds (2*$i)}}; if(-not $downloaded){throw 'Gradle download did not complete.'}; $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $env:TB_GRADLE_ZIP).Hash.ToLowerInvariant(); $expected=($env:TB_GRADLE_SHA).ToLowerInvariant(); if($actual -ne $expected){throw ('Gradle SHA-256 mismatch. Expected '+$expected+' got '+$actual)}; Add-Type -AssemblyName System.IO.Compression.FileSystem; $z=[IO.Compression.ZipFile]::OpenRead($env:TB_GRADLE_ZIP); $z.Dispose(); if(Test-Path $env:TB_GRADLE_HOME){Remove-Item -Recurse -Force $env:TB_GRADLE_HOME}; Expand-Archive -LiteralPath $env:TB_GRADLE_ZIP -DestinationPath $env:TB_TOOLS_DIR -Force"
if errorlevel 1 (
  set "LAST_ERROR=Verified Gradle 8.13 bootstrap failed. The builder rejects corrupt or checksum-mismatched downloads."
  exit /b 1
)
if exist "%GRADLE_ZIP%" del /Q "%GRADLE_ZIP%" >nul 2>&1
if not exist "%GRADLE_EXE%" (
  set "LAST_ERROR=Gradle archive verified but gradle.bat was not created at the expected location."
  exit /b 1
)
exit /b 0

:probe_gradle
if not exist "%GRADLE_EXE%" exit /b 1
call "%GRADLE_EXE%" "-Dorg.gradle.java.home=%JAVA_HOME%" --no-daemon --version > "%GRADLE_VERSION_FILE%" 2>&1
if errorlevel 1 exit /b 1
findstr /C:"Gradle %GRADLE_VERSION%" "%GRADLE_VERSION_FILE%" >nul
if errorlevel 1 exit /b 1
findstr /R /C:"Launcher JVM: 17" /C:"JVM:.*17\." "%GRADLE_VERSION_FILE%" >nul
if errorlevel 1 exit /b 1
exit /b 0

:verify_gradle
call :probe_gradle
if errorlevel 1 (
  if exist "%GRADLE_VERSION_FILE%" type "%GRADLE_VERSION_FILE%"
  set "LAST_ERROR=Gradle is not running as Gradle 8.13 on JDK 17. The build was blocked before compilation."
  exit /b 1
)
type "%GRADLE_VERSION_FILE%"
echo [OK] Gradle 8.13 is isolated on the builder's JDK 17 runtime.
exit /b 0

:find_android_sdk
set "SDK_CANDIDATE="
if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%" set "SDK_CANDIDATE=%ANDROID_SDK_ROOT%"
if not defined SDK_CANDIDATE if defined ANDROID_HOME if exist "%ANDROID_HOME%" set "SDK_CANDIDATE=%ANDROID_HOME%"
if not defined SDK_CANDIDATE if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_CANDIDATE=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK_CANDIDATE (
  set "LAST_ERROR=Android SDK not found. Install Android Studio once, or set ANDROID_SDK_ROOT / ANDROID_HOME."
  exit /b 1
)
set "ANDROID_HOME=%SDK_CANDIDATE%"
set "ANDROID_SDK_ROOT=%SDK_CANDIDATE%"
echo [OK] Android SDK: "%ANDROID_HOME%"
exit /b 0

:find_sdkmanager
set "SDKMANAGER="
if exist "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" (
  set "SDKMANAGER=%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat"
  exit /b 0
)
for /f "delims=" %%I in ('where /R "%ANDROID_HOME%\cmdline-tools" sdkmanager.bat 2^>nul') do if not defined SDKMANAGER set "SDKMANAGER=%%I"
if defined SDKMANAGER exit /b 0
if exist "%ANDROID_HOME%\tools\bin\sdkmanager.bat" (
  set "SDKMANAGER=%ANDROID_HOME%\tools\bin\sdkmanager.bat"
  exit /b 0
)
exit /b 1

:ensure_android_packages
set "PLATFORM_JAR=%ANDROID_HOME%\platforms\android-36\android.jar"
set "BUILD_TOOLS_DIR=%ANDROID_HOME%\build-tools\%BUILD_TOOLS_VERSION%"
set "AAPT_EXE=%BUILD_TOOLS_DIR%\aapt.exe"
if exist "%PLATFORM_JAR%" if exist "%AAPT_EXE%" exit /b 0

call :find_sdkmanager
if errorlevel 1 (
  set "LAST_ERROR=Android API 36 / Build Tools 35.0.0 are missing and sdkmanager.bat could not be found. Install Android SDK Command-line Tools in Android Studio."
  exit /b 1
)

echo [INFO] Installing missing Android SDK packages: API 36 + Build Tools %BUILD_TOOLS_VERSION%...
call "%SDKMANAGER%" "platforms;android-36" "build-tools;%BUILD_TOOLS_VERSION%"
if not errorlevel 1 goto :sdk_packages_verify

echo.
echo [WARN] SDK package installation failed. Unaccepted Android SDK licenses are a common cause.
echo [INFO] Android's license review will open now. Review and accept the required licenses, then the builder will retry once.
call "%SDKMANAGER%" --licenses
if errorlevel 1 (
  set "LAST_ERROR=Android SDK licenses were not completed. Open Android Studio ^> SDK Manager, accept the required licenses, and rerun."
  exit /b 1
)
call "%SDKMANAGER%" "platforms;android-36" "build-tools;%BUILD_TOOLS_VERSION%"
if errorlevel 1 (
  set "LAST_ERROR=Android API 36 / Build Tools installation still failed after the license review."
  exit /b 1
)

:sdk_packages_verify
if not exist "%PLATFORM_JAR%" (
  set "LAST_ERROR=Android Platform 36 installation did not produce android.jar."
  exit /b 1
)
if not exist "%AAPT_EXE%" (
  set "LAST_ERROR=Android Build Tools 35.0.0 installation did not produce aapt.exe."
  exit /b 1
)
echo [OK] Android API 36 + Build Tools %BUILD_TOOLS_VERSION% are ready.
exit /b 0

:resolve_mode
set "MODE="
if /I "%~1"=="debug" set "MODE=debug"
if /I "%~1"=="/debug" set "MODE=debug"
if /I "%~1"=="release" set "MODE=release"
if /I "%~1"=="/release" set "MODE=release"
if /I "%~1"=="both" set "MODE=both"
if /I "%~1"=="/both" set "MODE=both"
if defined MODE exit /b 0
if not "%~1"=="" (
  set "LAST_ERROR=Unknown build mode '%~1'. Use debug, release, or both."
  exit /b 1
)

set "INTERACTIVE=1"
echo.
echo What do you want to build?
echo   1. Debug APK
echo   2. Release AAB
echo   3. Both ^(recommended^)
set /p "CHOICE=Choose 1, 2, or 3 [3]: "
if "%CHOICE%"=="" set "CHOICE=3"
if "%CHOICE%"=="1" set "MODE=debug"
if "%CHOICE%"=="2" set "MODE=release"
if "%CHOICE%"=="3" set "MODE=both"
if not defined MODE (
  set "LAST_ERROR=Invalid choice. Choose 1, 2, or 3."
  exit /b 1
)
exit /b 0

:clear_outputs
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%" >nul 2>&1
del /Q "%DIST_DIR%\ToggleBay-debug.apk" >nul 2>&1
del /Q "%DIST_DIR%\ToggleBay-release.aab" >nul 2>&1
del /Q "%DIST_DIR%\BUILD_INFO.txt" >nul 2>&1
del /Q "%TOOLS_DIR%\apk-badging.txt" >nul 2>&1
exit /b 0

:run_build
set "TASKS="
if /I "%MODE%"=="debug" set "TASKS=assembleDebug"
if /I "%MODE%"=="release" set "TASKS=bundleRelease"
if /I "%MODE%"=="both" set "TASKS=assembleDebug bundleRelease"
if not defined TASKS (
  set "LAST_ERROR=Internal builder error: build task selection is empty."
  exit /b 1
)

echo.
echo [BUILD] clean %TASKS%
call "%GRADLE_EXE%" "-Dorg.gradle.java.home=%JAVA_HOME%" --no-daemon --stacktrace --console=plain clean %TASKS%
if errorlevel 1 (
  set "LAST_ERROR=Gradle build failed. The error above is from the actual project build; no stale output will be reported as success."
  exit /b 1
)
exit /b 0

:collect_and_verify
set "APK_SOURCE=%CD%\build\outputs\apk\debug\PowerToggles-debug.apk"
set "AAB_SOURCE=%CD%\build\outputs\bundle\release\PowerToggles-release.aab"
set "NEED_APK=0"
set "NEED_AAB=0"
if /I "%MODE%"=="debug" set "NEED_APK=1"
if /I "%MODE%"=="release" set "NEED_AAB=1"
if /I "%MODE%"=="both" (
  set "NEED_APK=1"
  set "NEED_AAB=1"
)

if "%NEED_APK%"=="1" (
  if not exist "%APK_SOURCE%" (
    set "LAST_ERROR=Gradle reported success but the expected debug APK is missing."
    exit /b 1
  )
  call :verify_archive "%APK_SOURCE%" apk
  if errorlevel 1 exit /b 1
  call :verify_apk_identity "%APK_SOURCE%"
  if errorlevel 1 exit /b 1
  copy /Y "%APK_SOURCE%" "%DIST_DIR%\ToggleBay-debug.apk" >nul
  if errorlevel 1 (
    set "LAST_ERROR=Debug APK built successfully but could not be copied into dist."
    exit /b 1
  )
)

if "%NEED_AAB%"=="1" (
  if not exist "%AAB_SOURCE%" (
    set "LAST_ERROR=Gradle reported success but the expected release AAB is missing."
    exit /b 1
  )
  call :verify_archive "%AAB_SOURCE%" aab
  if errorlevel 1 exit /b 1
  copy /Y "%AAB_SOURCE%" "%DIST_DIR%\ToggleBay-release.aab" >nul
  if errorlevel 1 (
    set "LAST_ERROR=Release AAB built successfully but could not be copied into dist."
    exit /b 1
  )
)

call :write_build_info
if errorlevel 1 exit /b 1
exit /b 0

:verify_archive
set "TB_VERIFY_PATH=%~1"
set "TB_VERIFY_KIND=%~2"
"%PS_EXE%" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; $f=Get-Item -LiteralPath $env:TB_VERIFY_PATH; if($f.Length -lt 1024){throw 'Artifact is unexpectedly small.'}; $z=[IO.Compression.ZipFile]::OpenRead($f.FullName); try{$names=@($z.Entries.FullName); if($env:TB_VERIFY_KIND -eq 'apk'){if($names -notcontains 'AndroidManifest.xml'){throw 'APK is missing AndroidManifest.xml'}; if(-not ($names | Where-Object { $_ -eq 'classes.dex' -or $_ -like 'classes*.dex' })){throw 'APK is missing classes.dex'}} elseif($env:TB_VERIFY_KIND -eq 'aab'){if($names -notcontains 'BundleConfig.pb'){throw 'AAB is missing BundleConfig.pb'}; if($names -notcontains 'base/manifest/AndroidManifest.xml'){throw 'AAB is missing base/manifest/AndroidManifest.xml'}} else {throw 'Unknown archive validation type'}} finally {$z.Dispose()}"
if errorlevel 1 (
  set "LAST_ERROR=Built %~2 failed ZIP/structure validation: %~1"
  exit /b 1
)
exit /b 0

:verify_apk_identity
set "APK_TO_CHECK=%~1"
"%AAPT_EXE%" dump badging "%APK_TO_CHECK%" > "%TOOLS_DIR%\apk-badging.txt" 2>&1
if errorlevel 1 (
  set "LAST_ERROR=aapt could not inspect the freshly built APK."
  exit /b 1
)
findstr /C:"package: name='%EXPECTED_PACKAGE%'" "%TOOLS_DIR%\apk-badging.txt" >nul
if errorlevel 1 (
  set "LAST_ERROR=Fresh APK package ID is not %EXPECTED_PACKAGE%."
  exit /b 1
)
findstr /C:"versionCode='%EXPECTED_VERSION_CODE%'" "%TOOLS_DIR%\apk-badging.txt" >nul
if errorlevel 1 (
  set "LAST_ERROR=Fresh APK versionCode is not %EXPECTED_VERSION_CODE%."
  exit /b 1
)
findstr /C:"versionName='%EXPECTED_VERSION_NAME%'" "%TOOLS_DIR%\apk-badging.txt" >nul
if errorlevel 1 (
  set "LAST_ERROR=Fresh APK versionName is not %EXPECTED_VERSION_NAME%."
  exit /b 1
)
findstr /C:"targetSdkVersion:'%EXPECTED_TARGET_SDK%'" "%TOOLS_DIR%\apk-badging.txt" >nul
if errorlevel 1 (
  set "LAST_ERROR=Fresh APK targetSdkVersion is not %EXPECTED_TARGET_SDK%."
  exit /b 1
)
echo [OK] Fresh APK identity verified: %EXPECTED_PACKAGE% v%EXPECTED_VERSION_NAME% ^(%EXPECTED_VERSION_CODE%^), target %EXPECTED_TARGET_SDK%.
exit /b 0

:write_build_info
> "%DIST_DIR%\BUILD_INFO.txt" echo ToggleBay builder=%BUILDER_VERSION%
>> "%DIST_DIR%\BUILD_INFO.txt" echo mode=%MODE%
>> "%DIST_DIR%\BUILD_INFO.txt" echo package=%EXPECTED_PACKAGE%
>> "%DIST_DIR%\BUILD_INFO.txt" echo versionName=%EXPECTED_VERSION_NAME%
>> "%DIST_DIR%\BUILD_INFO.txt" echo versionCode=%EXPECTED_VERSION_CODE%
>> "%DIST_DIR%\BUILD_INFO.txt" echo targetSdk=%EXPECTED_TARGET_SDK%
>> "%DIST_DIR%\BUILD_INFO.txt" echo gradle=%GRADLE_VERSION%
>> "%DIST_DIR%\BUILD_INFO.txt" echo jdk=17
set "TB_DIST_DIR=%DIST_DIR%"
"%PS_EXE%" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; $p=Join-Path $env:TB_DIST_DIR 'BUILD_INFO.txt'; Add-Content -LiteralPath $p -Value ('builtUtc='+[DateTime]::UtcNow.ToString('o')); $apk=Join-Path $env:TB_DIST_DIR 'ToggleBay-debug.apk'; $aab=Join-Path $env:TB_DIST_DIR 'ToggleBay-release.aab'; if(Test-Path $apk){Add-Content -LiteralPath $p -Value ('debugApkSha256='+(Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash.ToLowerInvariant())}; if(Test-Path $aab){Add-Content -LiteralPath $p -Value ('releaseAabSha256='+(Get-FileHash -Algorithm SHA256 -LiteralPath $aab).Hash.ToLowerInvariant())}"
if errorlevel 1 (
  set "LAST_ERROR=Artifacts built successfully but BUILD_INFO.txt could not be finalized."
  exit /b 1
)
exit /b 0

:fail
echo.
echo ============================================================
echo BUILD STOPPED SAFELY
echo ============================================================
echo [ERROR] %LAST_ERROR%
echo.
echo No stale dist artifact is being reported as a successful build.
echo If this message is unclear, copy this window's output back to Gate 2A Alfred.
echo.
if "%INTERACTIVE%"=="1" pause
popd
exit /b 1
