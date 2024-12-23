@echo off

REM Check for GPU or CPU execution
setlocal EnableDelayedExpansion
set CONFIG_FILE=config.yaml

REM Read the execution mode from config.yaml
for /f "tokens=2 delims=: " %%a in ('findstr /i "execution_mode" %CONFIG_FILE%') do (
    set EXECUTION_MODE=%%a
)
for /f "tokens=2 delims=: " %%a in ('findstr /i "compose_mode" %CONFIG_FILE%') do (
    set COMPOSE_MODE=%%a
)

REM Trim spaces and quotes
set EXECUTION_MODE=!EXECUTION_MODE: =!
set EXECUTION_MODE=!EXECUTION_MODE:'=!  
set EXECUTION_MODE=!EXECUTION_MODE:~0,-1!
set COMPOSE_MODE=!COMPOSE_MODE: =!
set COMPOSE_MODE=!COMPOSE_MODE:'=!  
set COMPOSE_MODE=!COMPOSE_MODE:~0,-1!




REM Check if the Ollama container exists and remove it if necessary
docker ps -a --filter "name=ollama" --format "{{.Names}}" | findstr /i "ollama" >nul
if !errorlevel!==0 (
    echo Removing existing Ollama container...
    docker rm -f ollama
)

REM Check if the Ollama-pull-llama container exists and remove it if necessary
docker ps -a --filter "name=ollama-pull-llama" --format "{{.Names}}" | findstr /i "ollama-pull-llama" >nul
if !errorlevel!==0 (
    echo Removing existing Ollama-pull-llama container...
    docker rm -f ollama-pull-llama
)

REM Run 
if /i "!EXECUTION_MODE!" == "gpu " (
    echo Running with GPU...
    if /i "!COMPOSE_MODE!" == "create " (
        docker compose --profile gpu-nvidia pull
        docker compose create && docker compose --profile gpu-nvidia up
    ) else (
        docker compose --profile gpu-nvidia up
    )
) else if /i "!EXECUTION_MODE!" == "cpu " (
    echo Running with CPU...
    if /i "!COMPOSE_MODE!" == "create " (
        docker compose --profile cpu pull
        docker compose create && docker compose --profile cpu up
    ) else (
        docker compose --profile cpu up
    )
) else (
    echo Invalid execution mode: !EXECUTION_MODE!
)

endlocal
