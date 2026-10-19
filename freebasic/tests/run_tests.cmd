@echo off
rem zip - compileaza si ruleaza testele FreeBASIC: legatura directa (nivelul 1) si clasa ZipArchive
rem (nivelul 2); compileaza si ruleaza si exemplele.
rem
rem   run_tests.cmd [cale\fbc64.exe]
rem
rem Fara argument se foloseste fbc64 din PATH. Optiuni suplimentare pentru fbc (de ex. alt generator
rem de cod):  set FBCOPTS=-gen gas64
rem Cere bin-win64\libzip.dll si bin-win64\libzip.dll.a (vezi build_native.cmd).
rem Biblioteca nivelului 2 se construieste in tests\out\lib, cu aceleasi optiuni ca testele.
rem Fiecare rulare a testelor scrie intr-un subdirector nou din tests\out.
rem test_margini (TestKit) se ruleaza daca TestKit e in %TESTKIT% sau langa depozit (..\TestKit).

setlocal
set "FBC=%~1"
if "%FBC%"=="" set "FBC=fbc64"
set "HERE=%~dp0"
set "ROOT=%HERE%.."
set "OUT=%HERE%out"
set "BIN=%ROOT%\bin-win64"

if not exist "%BIN%\libzip.dll.a" (
    echo bin-win64\libzip.dll.a lipseste: ruleaza intai build_native.cmd.
    goto :error
)
if not exist "%OUT%" mkdir "%OUT%"
copy /y "%BIN%\libzip.dll" "%OUT%\" >nul || goto :error

call "%ROOT%\build_lib.cmd" "%FBC%" "%OUT%\lib" %FBCOPTS% || goto :error

set "FLAGS=-w all %FBCOPTS% -i "%ROOT%\inc" -p "%OUT%\lib" -p "%BIN%""
"%FBC%" %FLAGS% -x "%OUT%\test_c.exe" "%HERE%test_c.bas" || goto :error
"%FBC%" %FLAGS% -x "%OUT%\test_fb.exe" "%HERE%test_fb.bas" || goto :error
"%FBC%" %FLAGS% -x "%OUT%\exemplu_c.exe" "%ROOT%\examples\exemplu_c.bas" || goto :error
"%FBC%" %FLAGS% -x "%OUT%\exemplu_fb.exe" "%ROOT%\examples\exemplu_fb.bas" || goto :error

"%OUT%\test_c.exe" "%OUT%" || goto :error
"%OUT%\test_fb.exe" "%OUT%" || goto :error
"%OUT%\exemplu_c.exe" "%OUT%" || goto :error
"%OUT%\exemplu_fb.exe" "%OUT%" || goto :error

rem ---- marginile (TestKit): dimensiuni de date, compresie, arhive stricate, nume, extragere, volum.
rem TestKit se cauta in %TESTKIT%, altfel langa depozit (..\TestKit); fara el, testul e sarit.
set "TSK=%TESTKIT%"
if "%TSK%"=="" set "TSK=%ROOT%\..\..\TestKit"
if exist "%TSK%\TestKit.bi" (
    "%FBC%" %FLAGS% -exx -i "%TSK%" -x "%OUT%\test_margini.exe" "%HERE%test_margini.bas" || goto :error
    "%OUT%\test_margini.exe" --timeout=300 --no-color -q || goto :error
) else (
    echo test_margini sarit: TestKit nu e in %TSK% ^(set TESTKIT=cale^)
)

echo toate testele au trecut
exit /b 0

:error
echo ESEC
exit /b 1
