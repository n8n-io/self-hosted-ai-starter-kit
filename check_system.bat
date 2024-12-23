@echo off
setlocal enabledelayedexpansion

REM Check CPU Information
echo Checking CPU Information...
wmic cpu get name,NumberOfCores,NumberOfLogicalProcessors /format:list > cpu_info.txt
set /p CPU_NAME=<cpu_info.txt
set /p CPU_CORES=<cpu_info.txt
set /p CPU_LOGICAL=<cpu_info.txt

REM Check GPU Information
echo Checking GPU Information...
wmic path win32_VideoController get name,AdapterRAM /format:list > gpu_info.txt
set /p GPU_NAME=<gpu_info.txt
set /p GPU_RAM=<gpu_info.txt

REM Check Docker Installation
echo Checking Docker Installation...
docker --version >nul 2>&1
if !errorlevel!==0 (
    echo Docker is installed.
    set DOCKER_INSTALLED=true
) else (
    echo Docker is not installed. Please install Docker to proceed.
    set DOCKER_INSTALLED=false
)

REM Check Python Installation
echo Checking Python Installation...
python --version >nul 2>&1
if !errorlevel!==0 (
    echo Python is installed.
) else (
    echo Python is not installed. Please install Python to proceed.
)

echo Debug Information:
echo Docker Installed: !DOCKER_INSTALLED!

REM Rate System Capability
echo.
echo Rating System Capability...

set SYSTEM_RATING=Poor
for /f "tokens=2 delims==" %%a in ('wmic cpu get NumberOfCores /format:list ^| findstr NumberOfCores') do (
    echo CPU Cores: %%a
    if %%a GEQ 8 (
        for /f "tokens=2 delims==" %%b in ('wmic path win32_VideoController get AdapterRAM /format:list ^| findstr AdapterRAM') do (
            echo GPU RAM: %%b
            if %%b GEQ 4293918720 (
                set SYSTEM_RATING=Excellent
            ) else (
                set SYSTEM_RATING=Good
            )
        )
    ) else if %%a GEQ 4 (
        set SYSTEM_RATING=Fair
    )
)

echo System Rating: !SYSTEM_RATING!

endlocal