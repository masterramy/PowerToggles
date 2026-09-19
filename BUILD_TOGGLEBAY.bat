@echo off
setlocal EnableExtensions DisableDelayedExpansion

pushd "%~dp0" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Could not enter the ToggleBay source directory.
  exit /b 1
)

title ToggleBay Builder
set "BUILDER_VERSION=2026-09-18-r8"
set "EXPECTED_PACKAGE=com.ramybaheeg.togglebay"
set "EXPECTED_VERSION_CODE=1"
set "EXPECTED_VERSION_NAME=1.0.0"
set "EXPECTED_TARGET_SDK=36"
set "GRADLE_VERSION=8.13"
set "GRADLE_SHA256=20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78"
set "BUILD_TOOLS_VERSION=35.0.0"
set "DOWNLOAD_TIMEOUT_SEC=600"
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

rem Neutralize host JVM/Gradle injection before the first private-JDK probe.
rem This is intentionally earlier than :activate_jdk so JAVA_TOOL_OPTIONS,
rem _JAVA_OPTIONS, JDK_JAVA_OPTIONS, or GRADLE_OPTS cannot poison bootstrap.
set "JAVA_OPTS="
set "JAVA_TOOL_OPTIONS="
set "_JAVA_OPTIONS="
set "JDK_JAVA_OPTIONS="
set "GRADLE_OPTS="

call :ensure_jdk
if errorlevel 1 goto :fail
call :activate_jdk
if errorlevel 1 goto :fail
call :ensure_gradle
if errorlevel 1 goto :fail
call :purge_incompatible_gradle_state
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
set "APK_SOURCE="
set "AAB_SOURCE="
set "NEED_APK=0"
set "NEED_AAB=0"
if /I "%MODE%"=="debug" set "NEED_APK=1"
if /I "%MODE%"=="release" set "NEED_AAB=1"
if /I "%MODE%"=="both" (
  set "NEED_APK=1"
  set "NEED_AAB=1"
)

if "%NEED_APK%"=="1" call :collect_debug_apk
if errorlevel 1 exit /b 1
if "%NEED_AAB%"=="1" call :collect_release_aab
if errorlevel 1 exit /b 1

call :write_build_info
if errorlevel 1 exit /b 1
exit /b 0

:collect_debug_apk
call :discover_single_artifact "%CD%\build\outputs\apk\debug" "*.apk" APK_SOURCE
if errorlevel 1 exit /b 1
if not exist "%APK_SOURCE%" (
  set "LAST_ERROR=Gradle reported success but the discovered debug APK path does not exist."
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
exit /b 0

:collect_release_aab
call :discover_single_artifact "%CD%\build\outputs\bundle\release" "*.aab" AAB_SOURCE
if errorlevel 1 exit /b 1
if not exist "%AAB_SOURCE%" (
  set "LAST_ERROR=Gradle reported success but the discovered release AAB path does not exist."
  exit /b 1
)
call :verify_archive "%AAB_SOURCE%" aab
if errorlevel 1 exit /b 1
copy /Y "%AAB_SOURCE%" "%DIST_DIR%\ToggleBay-release.aab" >nul
if errorlevel 1 (
  set "LAST_ERROR=Release AAB built successfully but could not be copied into dist."
  exit /b 1
)
exit /b 0

:discover_single_artifact
set "TB_FIND_DIR=%~1"
set "TB_FIND_PATTERN=%~2"
set "TB_FIND_OUT=%TOOLS_DIR%\artifact-path.txt"
if exist "%TB_FIND_OUT%" del /Q "%TB_FIND_OUT%" >nul 2>&1
if not exist "%TB_FIND_DIR%" (
  set "LAST_ERROR=Gradle reported success but output directory is missing: %TB_FIND_DIR%"
  exit /b 1
)
"%PS_EXE%" -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; $files=@(Get-ChildItem -LiteralPath $env:TB_FIND_DIR -Filter $env:TB_FIND_PATTERN -File); if($files.Count -ne 1){throw ('Expected exactly one '+$env:TB_FIND_PATTERN+' in '+$env:TB_FIND_DIR+'; found '+$files.Count+'. Files: '+(($files.Name)-join ', '))}; [IO.File]::WriteAllText($env:TB_FIND_OUT,$files[0].FullName,[Text.UTF8Encoding]::new($false))"
if errorlevel 1 (
  set "LAST_ERROR=Could not uniquely discover the fresh Gradle artifact in %TB_FIND_DIR%."
  exit /b 1
)
set "%~3="
for /f "usebackq delims=" %%A in ("%TB_FIND_OUT%") do set "%~3=%%A"
if not defined %~3 (
  set "LAST_ERROR=Artifact discovery returned an empty path."
  exit /b 1
)
echo [OK] Discovered fresh artifact:
type "%TB_FIND_OUT%"
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
