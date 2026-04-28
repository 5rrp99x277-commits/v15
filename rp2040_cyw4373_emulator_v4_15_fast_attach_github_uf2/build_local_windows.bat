@echo off
setlocal

if "%PICO_SDK_PATH%"=="" (
  echo ERROR: Set PICO_SDK_PATH first, for example:
  echo set PICO_SDK_PATH=C:\pico\pico-sdk
  exit /b 1
)

cmake -S . -B build -DPICO_BOARD=pico
if errorlevel 1 exit /b 1

cmake --build build -j
if errorlevel 1 exit /b 1

echo.
echo UF2 files:
dir /s /b build\*.uf2
