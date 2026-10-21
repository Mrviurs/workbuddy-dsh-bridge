@echo off
chcp 936 >nul
title WorkBuddy DSH Bridge - Status
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\wb-relay-status.ps1"
echo.
pause
