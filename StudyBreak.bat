@echo off
title Study Break Signal
:: Toggle NightWatch Study Break mode without forcing sleep.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StudyBreak.ps1"
