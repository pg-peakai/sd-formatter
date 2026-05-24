@echo off
title Rishav SD Card Formatter
net session >nul 2>&1
if not "%errorlevel%"=="0" goto elevate
goto run

:elevate
powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:run
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "irm https://raw.githubusercontent.com/pg-peakai/sd-formatter/main/dashboard.ps1 | iex"
exit /b
