@echo off
chcp 936 >nul
title WorkBuddy DSH Bridge - Stop
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\wb-relay-stop.ps1"
echo.
pause
