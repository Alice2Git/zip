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
    ├── test_fb.bas      nivelul 2: toate metodele, căi cu diacritice, UNC și \\?\
    └── test_margini.bas cu TestKit: dimensiuni de date și CRC, niveluri de compresie, citire pe bucăți, arhive stricate, nume de intrări, extragere periculoasă
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
- `tests\run_tests.cmd [fbc64]` construiește biblioteca nivelului 2 în `tests\out\lib`, apoi compilează și rulează testele și exemplele. Alt generator de cod se alege cu `set FBCOPTS=-gen gas64`. Fiecare rulare scrie într-un subdirector nou din `tests\out`. `test_margini.bas` rulează doar dacă [TestKit](https://github.com/Alice2Git/TestKit) e în `%TESTKIT%` sau lângă depozit (`..\TestKit`); altfel e sărit.

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
- Fără parolă, `zip_entry_fread` și `zip_extract` scriu fișierul și abia apoi verifică CRC-ul: la un CRC greșit întorc o eroare, dar fișierul rămâne pe disc. Cu parolă, verificarea se face înainte de scriere și nu rămâne nimic. `ExtractEntry` șterge fișierul nou la eșec (verificat în `test_margini.bas`).
- Arhivele create cu `'w'` sunt scrise în format zip64 (`zip_is64` = 1).
- `zip_entry_open` nu ține cont de majuscule; când mai multe intrări se potrivesc (nume duplicate sau care diferă doar prin majuscule), o găsește pe **ultima**, chiar dacă alta are exact numele cerut. `zip_entries_delete` compară numele **cu** majuscule. (Verificate în `test_margini.bas`.)
- La extragere (`zip_extract`, `zip_stream_extract`), `/` și `\` de la început și componentele făcute doar din puncte (`.`, `..`) se elimină, deci o intrare ca `../../x` sau `/abs` ajunge sub destinație, iar `C:\x` sau `\\?\C:\x` dau eroare. Extragerea se oprește la prima intrare cu eroare, iar cele scrise până atunci rămân. Pe NTFS, nume care diferă doar prin majuscule, sau printr-un punct ori spațiu la final, sunt același fișier: ultimul îl suprascrie pe primul, fără eroare. O cale finală mai lungă de 260 de caractere, sub o destinație fără `\\?\`, dă `ZIP_EMKDIR`. (Verificate în `test_margini.bas`.)

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
- Nivelul de compresie e între 0 (fără compresie) și 10 (`MZ_UBER_COMPRESSION`); un nivel negativ înseamnă nivelul implicit (6). Peste 10, `OpenFile` (în orice mod) și `CreateInMemory` întorc `ZIP_EINVLVL` și nu creează nimic. Biblioteca C verifică doar `nivel and &hF` și dă biții de sus mai departe ca flag-uri miniz: la nivelul 1, `zip_open` acceptă de exemplu 16 (stochează fără compresie) sau `&h400` (fiecare `zip_entry_open` pică apoi cu `ZIP_EINVLVL`).

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
| `OpenFile(cale, mod = ZipRead, nivel = 6, parolă = "")` | deschide un fișier; nivelul 0–10 contează doar la scriere; parola criptează (PKWARE) la scriere și decriptează la citire |
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
| `ExtractEntry(nume, cale)` | scrie intrarea într-un fișier; directorul lui trebuie să existe; la eșec (de exemplu CRC greșit) un fișier nou e șters, iar unul care exista poate rămâne suprascris |
| `DeleteEntries(nume())`, `DeleteEntriesAt(indecși())` | întorc numărul de intrări șterse |
| `ExtractAll(arhivă, director, apel = 0, date = 0)` (static) | directorul trebuie să existe; apelul invers primește calea fiecărui fișier extras; la eșec fișierele deja scrise rămân, inclusiv cel la care s-a oprit (cu date netestate, dacă CRC-ul lui e greșit) |
| `ExtractAllFromMemory(octeți, director, apel = 0, date = 0)` (static) | |
| `CreateFromFiles(arhivă, fișiere())` (static) | fiecare fișier intră sub numele lui, fără director |
| `ErrorText(cod)` (static) | |

`ZipExtractCallback` este `function(byref path as const ustring, byval userData as any ptr) as long`. O valoare negativă oprește extragerea, iar `ExtractAll` o întoarce: spre deosebire de `zip_extract`, oprirea se vede în rezultat.

## Corecturi în bibliotecă

Testele de pe Windows cu msvcrt (runtime-ul FreeBASIC) au găsit probleme în biblioteca C, corectate în acest fork:

- `fdfdb5d`, `078851e`: `zip_extract` și `zip_stream_extract` eșuau cu `ZIP_ENOFILE` pentru orice destinație, pentru că `_wstat` din msvcrt respinge un director cu separator la final. Rădăcina unui share (`\\server\share\`) își păstrează separatorul.
- `46bc5aa`: căile `\\?\` (`fwrite`, `zip_create`, extragere), plus `chmod`/`utime`/`remove` cu nume non-ASCII. Acestea treceau prin funcțiile înguste ale CRT, deci extragerea unei arhive cu atribute Unix eșua cu `ZIP_ENOPERM`, iar fișierele își pierdeau data.
- `zip_entry_extract` pe o intrare director întorcea 0 (cu parolă chema și apelul invers o dată, cu 0 octeți), în timp ce `zip_entry_read`, `zip_entry_noallocread` și `zip_entry_fread` o refuză. Acum întoarce și el `ZIP_EINVENTTYPE`, fără să cheme apelul invers. Găsit de `test_margini.bas`; testul C este `test_extract_dir_entry_rejected` din `test/test_read.c`.
- La scriere, `zip_entry_open` salvează `\` ca `/`, dar la citire `zip_entry_open` și `zip_entry_opencasesensitive` căutau numele exact, deci `"a\b.txt"` nu mai găsea intrarea scrisă cu același nume (`ZIP_ENOENT`), iar `zip_entries_delete` nu o ștergea. Acum căutarea încearcă întâi numele exact (pentru arhivele care păstrează `\`), apoi cu `/`, iar la ștergere `\` din numele dat se potrivește cu `/` din arhivă. Găsit de `test_margini.bas`; testele C sunt `test_entry_open_backslash` și `test_entries_delete_backslash` din `test/test_entry.c`.
- Pe Windows, `zip_extract` și `zip_stream_extract` (deci și `ExtractAll`) scriau o intrare cu `:` în nume (`"a:b.txt"`, `"C:rel.txt"`) într-un flux NTFS alternativ, lăsând pe disc un fișier gol `a`, iar o intrare cu nume de dispozitiv (`nul`, `dir/nul`) ajungea în dispozitiv. Extragerea raporta succes, dar datele erau ascunse sau pierdute. Acum o componentă cu `:` sau cu un nume de dispozitiv rezervat (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`, cu sau fără extensie, fără diferență de majuscule) dă `ZIP_EINVENTNAME`, iar extragerea se oprește la ea, ca la celelalte nume invalide. Găsit de `test_margini.bas`; testul C este `test_extract_windows_unsafe_names_rejected` din `test/test_extract.c`.
- O arhivă fără zip64 (de exemplu una făcută de alt program, deschisă cu `'a'`) care trecea de 65535 de intrări sau de 4 GB era distrusă la închidere, deși fiecare adăugare raporta succes. Biblioteca scrie singură antetele intrărilor, ocolind trecerea automată pe zip64 din miniz, deci `mz_zip_writer_finalize_archive` refuza cu `MZ_ZIP_TOO_MANY_FILES`, iar `zip_close` nu poate raporta eroarea. Intrările noi fuseseră deja scrise peste vechiul director central, iar cel nou nu mai era scris, așa că arhiva nu se mai deschidea (`ZIP_ERINIT`). Acum finalizarea trece arhiva pe zip64 când e nevoie. Găsit de `test_margini.bas`; testul C este `test_append_past_65535_entries_without_zip64` din `test/test_append.c`.
