@echo off
title WorkBuddy DSH Bridge - Legacy
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\wb-relay-start.ps1"
echo.
pause
