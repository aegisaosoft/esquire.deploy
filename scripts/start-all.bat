@echo off
echo ========================================
echo   Esquire - Starting all services
echo ========================================
echo.

echo [1/7] Starting Keycloak...
start "Keycloak" cmd /c "C:\aegis-miron\scripts\01-keycloak.bat"
echo Waiting 15 seconds for Keycloak to start...
timeout /t 15 /nobreak >nul

echo [2/7] Starting BizTree (port 3002)...
start "BizTree" cmd /c "C:\aegis-miron\scripts\02-bizTree.bat"
timeout /t 5 /nobreak >nul

echo [3/7] Starting EnyMan (port 3003)...
start "EnyMan" cmd /c "C:\aegis-miron\scripts\03-enyMan.bat"
timeout /t 5 /nobreak >nul

echo [4/7] Starting PacMan (port 3004)...
start "PacMan" cmd /c "C:\aegis-miron\scripts\04-pacMan.bat"
timeout /t 5 /nobreak >nul

echo [5/7] Starting KeySmith (port 3005)...
start "KeySmith" cmd /c "C:\aegis-miron\scripts\05-keySmith.bat"
timeout /t 5 /nobreak >nul

echo [6/7] Starting Gateway (port 7070)...
start "Gateway" cmd /c "C:\aegis-miron\scripts\06-gateway.bat"
timeout /t 5 /nobreak >nul

echo [7/7] Starting Frontend (port 4200)...
start "Frontend" cmd /c "C:\aegis-miron\scripts\07-frontend.bat"

echo.
echo ========================================
echo   All services started!
echo ========================================
echo   Keycloak:  http://localhost:8080  (admin/admin)
echo   Gateway:   http://localhost:7070
echo   Frontend:  http://localhost:4200
echo ========================================
pause
