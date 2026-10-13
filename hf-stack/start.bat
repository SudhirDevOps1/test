@echo off
REM =============================================================================
REM  Private Cloud Stack - Windows start script
REM
REM  Double-click this file. Bas itna hi karna hai.
REM  Pehli baar docker build 3-5 min lega, uske baad 30 sec.
REM =============================================================================
cd /d "%~dp0"

echo.
echo  [1/3] Docker check kar raha hun...
docker version >nul 2>&1
if errorlevel 1 (
    echo.
    echo    DOCKER NAHI MILA.
    echo.
    echo    Pehle ye install karo (free, 10 min):
    echo       https://www.docker.com/products/docker-desktop/
    echo.
    echo    Install ke baad PC restart karo, phir ye file dobara double-click karo.
    echo.
    pause
    exit /b 1
)
echo        OK - Docker chal raha hai.
echo.

echo  [2/3] .env file bana raha hun (agar nahi hai)...
if not exist .env (
    copy /Y .env.example .env >nul
    echo        .env bana diya. Isme apne password/keys daal sakta hai.
) else (
    echo        .env pehle se hai - usehi rehne diya.
)
echo.

echo  [3/3] Stack start kar raha hun (pehli baar 3-5 min)...
docker compose up -d --build
echo.

echo ============================================================
echo   AGAR SAB THIK HUA, to browser me kholo:
echo.
echo        http://localhost:7860
echo.
echo   Password kahan hai? Boot log me - is command se dekho:
echo.
echo        docker logs private-cloud-stack
echo.
echo   "BASIC_AUTH_PASSWORD secret is NOT set. A random one was made:"
echo   uske neeche jo line hai - wahi tera password hai.
echo.
echo   Band karna ho to:
echo        docker compose down
echo ============================================================
echo.
pause
