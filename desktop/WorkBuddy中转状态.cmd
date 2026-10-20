@echo off
title WorkBuddy DSH Bridge - Status
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Documents\deepseek-harness\default-workspace\workbuddy-dsh-bridge\scripts\wb-relay-status.ps1"
echo.
pause
