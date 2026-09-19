@echo off
title Study Break Launcher
:: Resolve Desktop path (supporting OneDrive folder redirection)
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[System.Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP_DIR=%%I"
if not defined DESKTOP_DIR set "DESKTOP_DIR=%USERPROFILE%\Desktop"

:: 1. Create marker file
echo Intentional Study Break - %date% %time% > "%DESKTOP_DIR%\break_marker.txt"

:: 2. Hibernate the laptop immediately (saves open tabs & RAM state to SSD)
shutdown.exe /h
