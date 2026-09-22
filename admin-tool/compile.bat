@echo off
echo Compiling CRM Admin Tool...
javac -encoding UTF-8 -source 8 -target 8 -cp ojdbc8.jar CrmAdminTool.java EncryptPassword.java
if %ERRORLEVEL% EQU 0 (
    echo.
    echo =============================================
    echo   Compile SUCCESS -- ready to run
    echo =============================================
) else (
    echo.
    echo =============================================
    echo   Compile FAILED -- check errors above
    echo =============================================
)
pause
