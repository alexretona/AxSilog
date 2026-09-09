@echo off
REM Wrapper for snapshot.ps1 — PowerShell's default execution policy on this
REM machine is Restricted, so invoke the script with a per-process bypass.
REM No machine-wide policy change needed. Forwards all arguments through.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0snapshot.ps1" %*
