@echo off
rem zip - construieste biblioteca statica a nivelului 2 (clasa ZipArchive) din freebasic\src:
rem
rem   build_lib.cmd [cale\fbc64.exe] [director_iesire] [optiuni fbc]
rem
rem Fara argumente se foloseste fbc64 din PATH. Rezultat: <director_iesire>\libzip_fb.a (implicit
rem freebasic\lib). Un program o foloseste cu
rem   fbc64 -i freebasic\inc -p freebasic\lib -p freebasic\bin-win64 program.bas
rem Optiunile fbc (de ex. -gen gas64) se dau dupa directorul de iesire.

setlocal
set "FBC=%~1"
if "%FBC%"=="" set "FBC=fbc64"
set "HERE=%~dp0"
set "OUT=%~2"
if "%OUT%"=="" set "OUT=%HERE%lib"
shift & shift
set "EXTRA="
:args
if "%~1"=="" goto :build
set "EXTRA=%EXTRA% %1"
shift
goto :args

:build
if not exist "%OUT%" mkdir "%OUT%"
"%FBC%" -lib -w all %EXTRA% -i "%HERE%inc" -x "%OUT%\libzip_fb.a" "%HERE%src\zipfb.bas" || goto :error
echo biblioteca: %OUT%\libzip_fb.a
exit /b 0

:error
echo ESEC la compilarea bibliotecii
exit /b 1
