@echo off
setlocal enabledelayedexpansion

:: Source and Destination paths
set SRC_DIR="C:\Users\souvi\AppData\Roaming\MetaQuotes\Terminal\6C3C6A11D1C3791DD4DBF45421BF8028\Tester\Logs"
set DEST_DIR="d:\Trading\PowerHedger\test"

echo Checking for the latest log file in:
echo %SRC_DIR%

:: Identify the latest log file based on filename (date)
:: Sorting by name (/o:n) since format is YYYYMMDD.log
set LATEST_LOG=
for /f "delims=" %%i in ('dir /b /o:n /a:-d %SRC_DIR%\*.log 2^>nul') do (
    set LATEST_LOG=%%i
)

if not "!LATEST_LOG!"=="" (
    echo Found latest log: !LATEST_LOG!
    echo Copying to %DEST_DIR%...
    
    :: Ensure destination exists
    if not exist %DEST_DIR% mkdir %DEST_DIR%
    
    :: powershell -Command "Get-Content -Path '%SRC_DIR%\!LATEST_LOG!' -Encoding Unicode | Set-Content -Path '%DEST_DIR%\!LATEST_LOG!' -Encoding UTF8"
    powershell -Command "Get-Content -Path '%SRC_DIR%\!LATEST_LOG!' -Encoding Unicode | Out-File -FilePath '%DEST_DIR%\!LATEST_LOG!' -Encoding utf8"
) else (
    echo Error: No log files found in the source directory.
)

echo.
echo Converting HTML reports in %DEST_DIR% to UTF-8...
for %%f in ("%DEST_DIR%\ReportTester-*.html") do (
    echo Converting %%~nxf...
    powershell -Command "(Get-Content -Path '%%f' -Encoding Unicode) | Out-File -FilePath '%%f' -Encoding utf8"
)

echo.
echo Process complete!
