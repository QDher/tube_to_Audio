@echo off
rem Starts Audio Extractor without leaving a console window open.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0AudioExtractor.ps1"
