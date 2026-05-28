@echo off

powershell -NoExit -Command "hermes-web-ui stop; Start-Sleep -Seconds 2; hermes-web-ui start; Start-Sleep -Seconds 2; exit"

exit