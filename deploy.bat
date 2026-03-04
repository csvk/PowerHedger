@echo off
setlocal

:: Source and Destination paths
set SRC_DIR=d:\Trading\PowerHedger
set DEST_DIR="C:\Users\souvi\AppData\Roaming\MetaQuotes\Terminal\6C3C6A11D1C3791DD4DBF45421BF8028\MQL5\Experts\PowerHedger"

echo Syncing main Expert Advisor file... 
echo %SRC_DIR%\PowerHedger.mq5

copy /Y "%SRC_DIR%\PowerHedger.mq5" %DEST_DIR%

echo.
echo Syncing Include files...
robocopy "%SRC_DIR%\Include" %DEST_DIR%\Include /E /XO /NJH /NJS /NDL /NC /NS /NP /V

echo.
echo Deployment complete!
