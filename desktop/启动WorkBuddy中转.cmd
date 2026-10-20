@echo off
title WorkBuddy DSH Bridge - Start
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Documents\deepseek-harness\default-workspace\workbuddy-dsh-bridge\scripts\wb-clean-start.ps1"
echo.
pause
