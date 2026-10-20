@echo off
title WorkBuddy DSH Bridge - Stop
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Documents\deepseek-harness\default-workspace\workbuddy-dsh-bridge\scripts\wb-relay-stop.ps1"
echo.
pause
