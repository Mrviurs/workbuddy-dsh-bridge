@echo off
chcp 936 >nul
title WorkBuddy DSH Bridge - Legacy
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\wb-relay-start.ps1"
echo.
pause
