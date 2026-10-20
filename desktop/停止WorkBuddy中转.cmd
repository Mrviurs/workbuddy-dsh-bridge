@echo off
title WorkBuddy DSH Bridge - Stop
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\wb-relay-stop.ps1"
echo.
pause
