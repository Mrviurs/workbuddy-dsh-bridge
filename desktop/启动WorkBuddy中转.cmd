@echo off
chcp 936 >nul
title WorkBuddy DSH Bridge - Start
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\wb-clean-start.ps1"
echo.
pause
