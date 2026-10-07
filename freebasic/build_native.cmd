@echo off
rem zip - construieste libzip.dll si biblioteca de import libzip.dll.a cu CMake si MinGW-w64 gcc din
rem MSYS2 si le copiaza in freebasic\bin-win64:
rem
rem   build_native.cmd [director_msys2]
rem
rem Implicit director_msys2 = C:\msys64 (cere pacman -S mingw-w64-x86_64-gcc make, si CMake in PATH).
rem Build-ul se face in build-mingw (langa CMakeLists.txt) si ruleaza si testele C ale bibliotecii.
rem FreeBASIC are nevoie de libzip.dll.a (biblioteca de import GNU), nu de un .lib facut cu MSVC.

setlocal
set "MSYS=%~1"
if "%MSYS%"=="" set "MSYS=C:\msys64"
set "HERE=%~dp0"
set "ROOT=%HERE%.."
set "PATH=%MSYS%\mingw64\bin;%MSYS%\usr\bin;%PATH%"

cmake -S "%ROOT%" -B "%ROOT%\build-mingw" -G "MSYS Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON || goto :error
cmake --build "%ROOT%\build-mingw" -j 4 || goto :error

rem testele C se leaga de libzip.dll, care sta in build-mingw
set "PATH=%ROOT%\build-mingw;%PATH%"
ctest --test-dir "%ROOT%\build-mingw" --output-on-failure || goto :error

if not exist "%HERE%bin-win64" mkdir "%HERE%bin-win64"
copy /y "%ROOT%\build-mingw\libzip.dll" "%HERE%bin-win64\" >nul || goto :error
copy /y "%ROOT%\build-mingw\libzip.dll.a" "%HERE%bin-win64\" >nul || goto :error
echo bin-win64: libzip.dll, libzip.dll.a
exit /b 0

:error
echo ESEC la construirea bibliotecii native
exit /b 1
