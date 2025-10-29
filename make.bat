@echo off
if exist env.bat del env.bat
for /f "tokens=*" %%a in (env) do echo set "%%a">>env.bat
call env.bat
del env.bat

if not "%WATCOM_BIN_DIR%" == "" set WATCOM_BIN_DIR=%WATCOM_BIN_DIR%\
"%WATCOM_BIN_DIR%wmake" %1 %2 %3 %4 %5 %6 %7 %8 %9
