@echo off
title WorkBuddy DSH Bridge - Start
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\wb-clean-start.ps1"
echo.
pause
