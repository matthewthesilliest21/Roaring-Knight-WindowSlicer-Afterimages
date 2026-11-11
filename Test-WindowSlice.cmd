@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0WindowSlice.ps1" -SelfTest
set result=%ERRORLEVEL%
if not "%result%"=="0" pause
exit /b %result%
