@echo off
title WorkBuddy DSH Bridge - Legacy
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Documents\deepseek-harness\default-workspace\workbuddy-dsh-bridge\scripts\wb-relay-start.ps1"
echo.
pause
