@echo off
title Study Break Signal
:: Toggle SleepSafe Study Break mode without forcing sleep.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0StudyBreak.ps1"
