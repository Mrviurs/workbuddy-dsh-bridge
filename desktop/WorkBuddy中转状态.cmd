@echo off
title WorkBuddy DSH Bridge - Status
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\wb-relay-status.ps1"
echo.
pause
