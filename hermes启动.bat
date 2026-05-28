@echo off
set "WT_DIR=C:\Users\HIBOY\Downloads\Microsoft.WindowsTerminal_1.24.10921.0_x64\terminal-1.24.10921.0"

cd /d "%WT_DIR%"

wt.exe cmd /c "hermes-web-ui stop & timeout /t 2 /nobreak >nul & hermes-web-ui start & timeout /t 2 /nobreak >nul & taskkill /F /IM WindowsTerminal.exe"

exit