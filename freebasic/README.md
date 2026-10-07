# zip pentru FreeBASIC

Legătura FreeBASIC la biblioteca [zip](../README.md) (miniz), pe două niveluri:

- **nivelul 1** (`zip_c.bi`): declarațiile celor 43 de funcții și ale tuturor constantelor din `src/zip.h`, unu la unu. Documentația din `zip.h` se aplică direct: numele, parametrii și regulile sunt aceleași.
- **nivelul 2** (`zipfb.bi`): clasa `ZipArchive`, cu nume și căi `USTRING`, date în `STRING` și erori ca coduri plus `LastError`. Vezi [Nivelul 2](#nivelul-2-clasa-ziparchive).

**Compilator:** FBC-Modern (ramura `lambda-fixes` din `Alice2Git/FBC-Modern`), pe 64 de biți. Nivelul 1 și `exemplu_c.bas` merg și cu FreeBASIC 1.10 standard; nivelul 2 folosește `USTRING` și `defer`, deci cere FBC-Modern. Ambele niveluri trec testele cu ambele generatoare de cod (`gcc` și `gas64`).

## Structura

```
freebasic/
├── build_native.cmd     construiește libzip.dll + libzip.dll.a (CMake, MSYS2 gcc) și le copiază în bin-win64
├── build_lib.cmd        construiește lib\libzip_fb.a (nivelul 2)
├── bin-win64/           libzip.dll, libzip.dll.a (generate, nu sunt în git)
├── lib/                 libzip_fb.a (generată, nu e în git)
├── inc/
│   ├── zip_c.bi         nivelul 1
│   └── zipfb.bi         nivelul 2 (include zip_c.bi)
├── src/zipfb.bas        implementarea nivelului 2
├── examples/
│   ├── exemplu_c.bas    nivelul 1: creare, listare, citire
│   └── exemplu_fb.bas   nivelul 2: creare, listare, citire, extragere, arhivă în memorie
└── tests/
    ├── run_tests.cmd    compilează și rulează testele și exemplele
    ├── test_c.bas       nivelul 1: fiecare grup de funcții din zip.h
    └── test_fb.bas      nivelul 2: toate metodele, căi cu diacritice, UNC și \\?\
```

## Compilare

Partea nativă se compilează numai cu MinGW-w64 gcc din MSYS2 (`C:\msys64\mingw64`, runtime `msvcrt.dll`, la fel ca FreeBASIC), cu CMake. Verificat pe 7 octombrie 2026 cu gcc 16.1.0, CMake 4.x și FBC-Modern 1.20.0. Comenzile se rulează din `freebasic\`:

```bat
build_native.cmd
build_lib.cmd <cale\fbc64.exe>
tests\run_tests.cmd <cale\fbc64.exe>
```

- `build_native.cmd [director_msys2]` rulează CMake în `..\build-mingw`, apoi testele C ale bibliotecii (`ctest`), și copiază `libzip.dll` și `libzip.dll.a` în `bin-win64`. DLL-ul depinde doar de `KERNEL32.dll` și `msvcrt.dll`.
- `build_lib.cmd [fbc64] [director_ieșire] [opțiuni fbc]` face `lib\libzip_fb.a`. Opțiunile (de exemplu `-gen gas64`) se dau după directorul de ieșire.
- `tests\run_tests.cmd [fbc64]` construiește biblioteca nivelului 2 în `tests\out\lib`, apoi compilează și rulează testele și exemplele. Alt generator de cod se alege cu `set FBCOPTS=-gen gas64`. Fiecare rulare scrie într-un subdirector nou din `tests\out`.

**Numai `libzip.dll.a`, niciodată un `.lib` de MSVC.** FreeBASIC leagă cu linkerul GNU, care are nevoie de biblioteca de import GNU.

Un program se compilează cu:

```bat
fbc64 -i freebasic\inc -p freebasic\bin-win64 program.bas                    (nivelul 1)
fbc64 -i freebasic\inc -p freebasic\lib -p freebasic\bin-win64 program.bas   (nivelul 2)
```

`libzip.dll` trebuie să stea lângă executabil.

## Nivelul 1: legătura directă

```basic
#include once "zip_c.bi"

dim as zip_t ptr z = zip_open("arhiva.zip", ZIP_DEFAULT_COMPRESSION_LEVEL, asc("w"))
dim as string text = "Salut"
zip_entry_open(z, "salut.txt")
zip_entry_write(z, strptr(text), len(text))
zip_entry_close(z)
zip_close(z)
```

### Tipuri

| C | FreeBASIC |
|---|---|
| `char mode` | `byte`: `asc("r")`, `asc("w")`, `asc("a")`, `asc("d")` |
| `size_t` | `uinteger` |
| `ssize_t` | `integer` (lățimea unui pointer, ca `ssize_t` pe Windows) |
| `uint64_t`, `unsigned long long` | `ulongint` |
| `unsigned int` | `ulong` |
| `const char *` (nume, căi) | `const zstring ptr`, șir UTF-8 |
| `const char *stream` | `const any ptr` |
| `FILE *` | `FILE ptr` din `crt/stdio.bi` |

Parametrii al căror nume e cuvânt rezervat în FreeBASIC au primit `_`: `len_`, `dir_`, `data_`.

### Reguli

- **Toate căile și numele de intrări sunt UTF-8.** Pe Windows biblioteca le convertește la UTF-16 și apelează funcțiile `_w*`. Merg căile UNC (`\\server\share\...`, și cu `/`), prefixul `\\?\` (inclusiv căi mai lungi de 260 de caractere) și diacriticele în căi și în numele intrărilor.
- Memoria întoarsă de `zip_entry_read` și `zip_stream_copy` e alocată cu `malloc` din `msvcrt.dll` și se eliberează cu `deallocate`.
- `zip_stream_open` **nu copiază** bufferul: el trebuie să rămână valid până la `zip_stream_close`. În modul `'d'` rezultatul se ia cu `zip_stream_copy`.
- `zip_extract` și `zip_stream_extract` cer ca directorul de destinație să existe; subdirectoarele din arhivă le creează singure.

### Comportamente de știut (verificate în `test_c.bas`)

- La citire, `zip_entry_name` întoarce **numele cerut** la `zip_entry_open` (de exemplu `"A.TXT"`), nu pe cel din arhivă. Numele din arhivă se obține după `zip_entry_openbyindex`.
- Un apel invers al lui `zip_extract` care întoarce o valoare negativă oprește extragerea, dar `zip_extract` întoarce **0**.
- O intrare criptată citită fără parolă dă `ZIP_EMEMNOALLOC` (-18), nu `ZIP_EPASSWD`. Cu parolă greșită dă `ZIP_EPASSWD`.
- Dacă `zip_entry_fwrite` eșuează (de exemplu fișierul nu există), intrarea deschisă rămâne în arhivă, goală, iar codul întors este `ZIP_ENOENT`.
- Arhivele create cu `'w'` sunt scrise în format zip64 (`zip_is64` = 1).

## Nivelul 2: clasa ZipArchive

```basic
#include once "zipfb.bi"

dim as ZipArchive zip
if zip.OpenFile("arhivă.zip", ZipWrite) < 0 then
    print zip.LastErrorText()
    end 1
end if
zip.AddText("salut.txt", "Bună ziua!")       '' textul se scrie UTF-8
zip.AddFile("poze/vară.jpg", "C:\Poze\vară.jpg")
zip.Close()                                  '' sau în destructor

zip.OpenFile("arhivă.zip")
dim as ZipEntryInfo entries()
for i as integer = 0 to zip.ListEntries(entries()) - 1
    print entries(i).Name, entries(i).Size
next
dim as ustring text
zip.ReadText("salut.txt", text)

ZipArchive.ExtractAll("arhivă.zip", "C:\Destinație")
```

### Reguli

- Metodele întorc 0 (sau un număr, la `ListEntries` și `Delete*`) la succes și un cod `ZIP_E*` negativ la eșec. Ultimul cod rămâne în `LastError` (0 după un succes), iar textul lui în `LastErrorText()`. Metodele statice întorc doar codul.
- Numele și căile sunt `USTRING`; conversia la UTF-8 se face în clasă. Datele intrărilor sunt `STRING` (octeți). `AddText` și `ReadText` lucrează cu text UTF-8.
- Fiecare metodă deschide și închide singură intrarea. Nu rămâne nimic deschis între apeluri.
- Un obiect nu se copiază. `OpenFile`, `OpenMemory` și `CreateInMemory` închid întâi arhiva deschisă; destructorul o închide și el. O arhivă scrisă într-un fișier se finalizează la închidere.

### Moduri

| Mod | Deschidere | Metode permise |
|---|---|---|
| `ZipRead` | `OpenFile`, `OpenMemory` | `GetEntry`, `FindEntry`, `Contains`, `ListEntries`, `Read*`, `ExtractEntry` |
| `ZipWrite` | `OpenFile`, `CreateInMemory` | `AddBytes`, `AddText`, `AddFile`, `AddDirectory` |
| `ZipAppend` | `OpenFile` | ca la `ZipWrite` |
| `ZipDelete` | `OpenFile`, `OpenMemory` | `DeleteEntries`, `DeleteEntriesAt` |

Celelalte metode întorc `ZIP_EINVMODE` și nu ating arhiva. În biblioteca C, `zip_entry_open` într-un mod de scriere ar adăuga o intrare nouă. `Count`, `IsZip64`, `ToBytes` și `Close` merg în orice mod.

### Membri

| Membru | Ce face |
|---|---|
| `OpenFile(cale, mod = ZipRead, nivel = 6, parolă = "")` | deschide un fișier; parola criptează (PKWARE) la scriere și decriptează la citire |
| `OpenMemory(octeți, mod = ZipRead, parolă = "")` | deschide o arhivă din memorie (`ZipRead` sau `ZipDelete`); datele se copiază în obiect |
| `CreateInMemory(nivel = 6, parolă = "")` | arhivă nouă în memorie |
| `ToBytes(octeți)` | octeții unei arhive din memorie; după el, o arhivă creată în memorie nu mai primește intrări |
| `Close()`, `IsOpen`, `Mode` | |
| `LastError`, `LastErrorText()` | |
| `Count`, `IsZip64()` | |
| `GetEntry(index, info)`, `FindEntry(nume, info)`, `Contains(nume)` | căutarea după nume nu ține cont de majuscule; `info.Name` e numele din arhivă |
| `ListEntries(entries())` | redimensionează `entries()` la `0..n-1` și întoarce `n` |
| `AddBytes(nume, octeți)`, `AddText(nume, text)` | |
| `AddFile(nume, cale)` | verifică întâi că fișierul există (altfel `ZIP_ENOFILE`), ca să nu rămână o intrare goală |
| `AddDirectory(nume)` | intrare `nume/` |
| `ReadBytes(nume, octeți)`, `ReadBytesAt(index, octeți)`, `ReadText(nume, text)` | un director dă `ZIP_EINVENTTYPE` |
| `ExtractEntry(nume, cale)` | scrie intrarea într-un fișier; directorul lui trebuie să existe |
| `DeleteEntries(nume())`, `DeleteEntriesAt(indecși())` | întorc numărul de intrări șterse |
| `ExtractAll(arhivă, director, apel = 0, date = 0)` (static) | directorul trebuie să existe; apelul invers primește calea fiecărui fișier extras |
| `ExtractAllFromMemory(octeți, director, apel = 0, date = 0)` (static) | |
| `CreateFromFiles(arhivă, fișiere())` (static) | fiecare fișier intră sub numele lui, fără director |
| `ErrorText(cod)` (static) | |

`ZipExtractCallback` este `function(byref path as const ustring, byval userData as any ptr) as long`. O valoare negativă oprește extragerea, iar `ExtractAll` o întoarce: spre deosebire de `zip_extract`, oprirea se vede în rezultat.

## Corecturi în bibliotecă

Testele de pe Windows cu msvcrt (runtime-ul FreeBASIC) au găsit probleme în biblioteca C, corectate în acest fork:

- `fdfdb5d`, `078851e`: `zip_extract` și `zip_stream_extract` eșuau cu `ZIP_ENOFILE` pentru orice destinație, pentru că `_wstat` din msvcrt respinge un director cu separator la final. Rădăcina unui share (`\\server\share\`) își păstrează separatorul.
- `46bc5aa`: căile `\\?\` (`fwrite`, `zip_create`, extragere), plus `chmod`/`utime`/`remove` cu nume non-ASCII. Acestea treceau prin funcțiile înguste ale CRT, deci extragerea unei arhive cu atribute Unix eșua cu `ZIP_ENOPERM`, iar fișierele își pierdeau data.
