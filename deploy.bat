@echo off
setlocal

:: Get version from argument
set VERSION=%~1
if "%VERSION%"=="" (
    echo Error: No version specified.
    echo Usage: deploy.bat [version] (e.g., deploy.bat v1)
    exit /b 1
)

:: Source and Destination paths
set BASE_DIR=d:\Trading\PowerHedger
set SRC_DIR=%BASE_DIR%\%VERSION%
set DEST_DIR="C:\Users\souvi\AppData\Roaming\MetaQuotes\Terminal\6C3C6A11D1C3791DD4DBF45421BF8028\MQL5\Experts\PowerHedger"

:: Check if version directory exists
if not exist "%SRC_DIR%" (
    echo Error: Version directory %VERSION% does not exist at %SRC_DIR%
    exit /b 1
)

echo Deploying version: %VERSION%
echo Syncing main Expert Advisor file... 
echo %SRC_DIR%\PowerHedger.mq5

copy /Y "%SRC_DIR%\PowerHedger.mq5" %DEST_DIR%

echo.
echo Syncing Include files...
robocopy "%SRC_DIR%\Include" %DEST_DIR%\Include /E /XO /NJH /NJS /NDL /NC /NS /NP /V

echo.
echo Deployment complete!
exit /b 0
