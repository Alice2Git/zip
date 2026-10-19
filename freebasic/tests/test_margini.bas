'' test_margini.bas - marginile legaturii FreeBASIC cu TestKit, dincolo de test_c si test_fb:
'' dimensiuni de date si CRC calculat independent, niveluri de compresie, citire pe bucati (nivelul 1),
'' arhive stricate, nume de intrari, extragere periculoasa.
''
''   fbc64 -w all -exx test_margini.bas -i ..\inc -i ..\..\..\TestKit -p out\lib -p ..\bin-win64
''   test_margini [--filter=Date.*] [--isolate] [-v]          (libzip.dll langa exe)
''
'' Fisierele de lucru stau in <director_exe>\margini\<Suita.Nume>, sterse la inceputul fiecarui test.

#include once "zipfb.bi"
#include once "windows.bi"
#include once "crt/string.bi"
#include once "TestKit.bi"

'' ================================================================== ajutoare

'' CRC-32 (IEEE 802.3, polinomul reflectat EDB88320), independent de miniz
dim shared as ulong CRC_TAB(0 to 255)
for i as long = 0 to 255
    dim as ulong c = i
    for k as long = 0 to 7
        if c and 1 then c = &hEDB88320 xor (c shr 1) else c = c shr 1
    next
    CRC_TAB(i) = c
next

function Crc32Of(byref s as const string) as ulong
    dim as ulong c = &hFFFFFFFF
    for i as integer = 0 to len(s) - 1
        c = CRC_TAB((c xor s[i]) and 255) xor (c shr 8)
    next
    return not c
end function

'' felul datelor: zerouri (foarte comprimabile), aleatoare (necomprimabile), text (comprimabil normal)
enum DataKind
    KindZero
    KindRandom
    KindText
end enum

function KindName(byval k as DataKind) as string
    select case k
    case KindZero : return "zero"
    case KindRandom : return "aleator"
    case else : return "text"
    end select
end function

'' date deterministe: aceeasi dimensiune si acelasi fel dau mereu aceiasi octeti
function MakeData(byval size as integer, byval k as DataKind, byval seed as ulong = 2463534242) as string
    dim as string s = string(size, 0)
    select case k
    case KindRandom
        dim as ulong x = seed
        for i as integer = 0 to size - 1
            x xor= x shl 13 : x xor= x shr 17 : x xor= x shl 5       '' xorshift32
            s[i] = x and 255
        next
    case KindText
        dim as string w = "Lorem ipsum dolor sit amet, consectetur adipiscing elit 0123456789" & chr(13, 10)
        for i as integer = 0 to size - 1
            s[i] = w[i mod len(w)]
        next
    end select
    return s
end function

'' primul octet diferit (-1 = sirurile sunt egale); la lungimi diferite, lungimea mai mica
function FirstDiff(byref a as const string, byref b as const string) as integer
    dim as integer n = len(a)
    if len(b) < n then n = len(b)
    for i as integer = 0 to n - 1
        if a[i] <> b[i] then return i
    next
    if len(a) <> len(b) then return n
    return -1
end function

function FileExists(byref p as const ustring) as boolean
    dim as DWORD a = GetFileAttributesW(p)
    return a <> INVALID_FILE_ATTRIBUTES andalso (a and FILE_ATTRIBUTE_DIRECTORY) = 0
end function

function ReadAll(byref p as const ustring) as string
    dim as HANDLE h = CreateFileW(p, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, 0, 0)
    if h = INVALID_HANDLE_VALUE then return ""
    dim as LARGE_INTEGER size
    GetFileSizeEx(h, @size)
    dim as string s = space(size.QuadPart)
    dim as DWORD got = 0
    if size.QuadPart > 0 then ReadFile(h, strptr(s), size.QuadPart, @got, 0)
    CloseHandle(h)
    return left(s, got)
end function

function WriteAll(byref p as const ustring, byref s as const string) as boolean
    dim as HANDLE h = CreateFileW(p, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0)
    if h = INVALID_HANDLE_VALUE then return false
    dim as DWORD written = 0
    if len(s) > 0 then WriteFile(h, strptr(s), len(s), @written, 0)
    CloseHandle(h)
    return written = len(s)
end function

'' sterge recursiv continutul directorului p (p ramane)
sub ClearDir(byref p as const ustring)
    dim as WIN32_FIND_DATAW fd
    dim as HANDLE h = FindFirstFileW(p & "\*", @fd)
    if h = INVALID_HANDLE_VALUE then exit sub
    do
        dim as ustring n = fd.cFileName
        if n <> "." andalso n <> ".." then
            dim as ustring full = p & "\" & n
            if fd.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY then
                ClearDir(full)
                RemoveDirectoryW(full)
            else
                SetFileAttributesW(full, FILE_ATTRIBUTE_NORMAL)
                DeleteFileW(full)
            end if
        end if
    loop while FindNextFileW(h, @fd)
    FindClose(h)
end sub

'' director de lucru gol, propriu testului curent: <exe>\margini\<Suita.Nume>
function WorkDir() as ustring
    dim as ustring root = exepath & "\margini"
    CreateDirectoryW(root, 0)
    dim as ustring d = root & "\" & TestName()
    CreateDirectoryW(d, 0)
    ClearDir(d)
    return d
end function

'' dimensiunile incercate: capete mici, granitele blocurilor de 64 KB ale deflate, cativa MB
dim shared as integer SIZES(...) = { 0, 1, 2, 255, 256, 65535, 65536, 65537, 1048575, 4194307 }

function EntryName(byval s as integer, byval k as DataKind) as string
    return KindName(k) & "_" & s & ".bin"
end function

'' verifica toate intrarile scrise de AddAllSizes intr-o arhiva deschisa pentru citire
sub CheckAllSizes(byref z as ZipArchive)
    REQUIRE_EQ( z.Count, clngint((ubound(SIZES) + 1) * 3) )
    for k as long = KindZero to KindText
        for i as long = 0 to ubound(SIZES)
            TEST_CONTEXT( EntryName(SIZES(i), k) )
            dim as string want = MakeData(SIZES(i), k)
            dim as ZipEntryInfo info
            REQUIRE_EQ( z.FindEntry(EntryName(SIZES(i), k), info), 0 )
            CHECK_EQ( info.Size, culngint(SIZES(i)) )
            CHECK_EQ( info.Crc32, Crc32Of(want) )
            dim as string got
            CHECK_EQ( z.ReadBytes(EntryName(SIZES(i), k), got), 0 )
            dim as integer d = FirstDiff(got, want)
            CHECK_MSG( d = -1, "primul octet diferit la " & d & " (citit " & len(got) & ", scris " & len(want) & ")" )
        next
    next
end sub

function AddAllSizes(byref z as ZipArchive) as boolean
    for k as long = KindZero to KindText
        for i as long = 0 to ubound(SIZES)
            if z.AddBytes(EntryName(SIZES(i), k), MakeData(SIZES(i), k)) <> 0 then return false
        next
    next
    return true
end function

'' ================================================================== 1. dimensiuni de date si CRC

'' CRC-ul propriu, pe vectorii cunoscuti: altfel comparatiile de mai jos nu spun nimic
TEST_CASE( Date, CrcPropriu )
    CHECK_EQ( Crc32Of(""), 0ul )
    CHECK_EQ( Crc32Of("123456789"), &hCBF43926ul )
    CHECK_EQ( Crc32Of("The quick brown fox jumps over the lazy dog"), &h414FA339ul )
END_TEST_CASE

TEST_CASE( Date, DimensiuniInMemorie )
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_TRUE( AddAllSizes(w) )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    w.Close()

    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    CheckAllSizes(r)
END_TEST_CASE

TEST_CASE( Date, DimensiuniInFisier )
    dim as ustring zipPath = WorkDir() & "\dimensiuni.zip"
    dim as ZipArchive w
    REQUIRE_EQ( w.OpenFile(zipPath, ZipWrite), 0 )
    REQUIRE_TRUE( AddAllSizes(w) )
    w.Close()

    dim as ZipArchive r
    REQUIRE_EQ( r.OpenFile(zipPath), 0 )
    CheckAllSizes(r)
END_TEST_CASE

'' citirea dupa index da intrarile in ordinea in care au fost adaugate
TEST_CASE( Date, OrdineaDupaIndex )
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_TRUE( AddAllSizes(w) )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )

    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    dim as integer idx = 0
    for k as long = KindZero to KindText
        for i as long = 0 to ubound(SIZES)
            TEST_CONTEXT( "index " & idx )
            dim as ZipEntryInfo info
            REQUIRE_EQ( r.GetEntry(idx, info), 0 )
            dim as ustring wantName = EntryName(SIZES(i), k)
            CHECK_EQ( info.Name, wantName )
            CHECK_EQ( info.Index, idx )
            dim as string got
            CHECK_EQ( r.ReadBytesAt(idx, got), 0 )
            CHECK_EQ( clngint(len(got)), clngint(SIZES(i)) )
            CHECK_EQ( Crc32Of(got), info.Crc32 )
            idx += 1
        next
    next
END_TEST_CASE

'' AddFile (zip_entry_fwrite) si ExtractEntry (zip_entry_fread) pe un fisier de cativa MB, citit in bucati
TEST_CASE( Date, FisierMareDusIntors )
    dim as ustring d = WorkDir()
    for k as long = KindZero to KindText
        TEST_CONTEXT( KindName(k) )
        dim as string want = MakeData(4194307, k, 12345 + k)
        REQUIRE_TRUE( WriteAll(d & "\sursa.bin", want) )
        dim as ZipArchive w
        REQUIRE_EQ( w.OpenFile(d & "\fisier.zip", ZipWrite), 0 )
        REQUIRE_EQ( w.AddFile("sursa.bin", d & "\sursa.bin"), 0 )
        w.Close()

        dim as ZipArchive r
        REQUIRE_EQ( r.OpenFile(d & "\fisier.zip"), 0 )
        dim as ZipEntryInfo info
        REQUIRE_EQ( r.FindEntry("sursa.bin", info), 0 )
        CHECK_EQ( info.Crc32, Crc32Of(want) )
        REQUIRE_EQ( r.ExtractEntry("sursa.bin", d & "\extras.bin"), 0 )
        r.Close()
        dim as string got = ReadAll(d & "\extras.bin")
        dim as integer diff = FirstDiff(got, want)
        CHECK_MSG( diff = -1, "primul octet diferit la " & diff & " (extras " & len(got) & ", scris " & len(want) & ")" )
    next
END_TEST_CASE

'' dimensiunea comprimata: zerourile se comprima mult, iar datele aleatoare nu depasesc limita
'' deflateBound din zlib (miniz le scrie in blocuri stocate de 32 KB, cu 5 octeti de antet fiecare)
TEST_CASE( Date, DimensiuneComprimata )
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_TRUE( AddAllSizes(w) )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )

    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    for i as long = 0 to ubound(SIZES)
        dim as longint s = SIZES(i)
        if s < 65536 then continue for
        TEST_CONTEXT( "dimensiune " & s )
        dim as ZipEntryInfo z, a
        REQUIRE_EQ( r.FindEntry(EntryName(s, KindZero), z), 0 )
        REQUIRE_EQ( r.FindEntry(EntryName(s, KindRandom), a), 0 )
        CHECK_MSG( z.CompressedSize * 100 < culngint(s), "zerouri: " & z.CompressedSize & " din " & s )
        dim as longint limita = s + (s shr 12) + (s shr 14) + (s shr 25) + 13
        CHECK_MSG( clngint(a.CompressedSize) <= limita, "aleator: " & a.CompressedSize & " din " & s & ", limita " & limita )
    next
END_TEST_CASE

'' ================================================================== 2. niveluri de compresie

const LEVEL_DATA_SIZE = 300007

'' o arhiva in memorie cu cele trei feluri de date, la nivelul dat
function LevelArchive(byval level as long, byref bytes as string) as long
    dim as ZipArchive w
    dim as long e = w.CreateInMemory(level)
    if e <> 0 then return e
    for k as long = KindZero to KindText
        e = w.AddBytes(KindName(k) & ".bin", MakeData(LEVEL_DATA_SIZE, k))
        if e <> 0 then return e
    next
    return w.ToBytes(bytes)
end function

'' dimensiunea comprimata a intrarii de felul k dintr-o arhiva facuta de LevelArchive
function CompSize(byref bytes as const string, byval k as DataKind) as longint
    dim as ZipArchive r
    dim as ZipEntryInfo info
    if r.OpenMemory(bytes) <> 0 orelse r.FindEntry(KindName(k) & ".bin", info) <> 0 then return -1
    return info.CompressedSize
end function

'' fiecare nivel 0-10 (10 = MZ_UBER_COMPRESSION) citeste inapoi exact datele, in memorie si in fisier
TEST_CASE( Niveluri, DusIntorsLaFiecareNivel )
    dim as ustring d = WorkDir()
    for level as long = 0 to 10
        for inFile as long = 0 to 1
            TEST_CONTEXT( "nivel " & level & iif(inFile, ", fisier", ", memorie") )
            dim as ZipArchive r
            if inFile then
                dim as ZipArchive w
                REQUIRE_EQ( w.OpenFile(d & "\nivel.zip", ZipWrite, level), 0 )
                for k as long = KindZero to KindText
                    REQUIRE_EQ( w.AddBytes(KindName(k) & ".bin", MakeData(LEVEL_DATA_SIZE, k)), 0 )
                next
                w.Close()
                REQUIRE_EQ( r.OpenFile(d & "\nivel.zip"), 0 )
            else
                dim as string bytes
                REQUIRE_EQ( LevelArchive(level, bytes), 0 )
                REQUIRE_EQ( r.OpenMemory(bytes), 0 )
            end if
            for k as long = KindZero to KindText
                TEST_CONTEXT( KindName(k) )
                dim as string want = MakeData(LEVEL_DATA_SIZE, k), got
                dim as ZipEntryInfo info
                REQUIRE_EQ( r.FindEntry(KindName(k) & ".bin", info), 0 )
                CHECK_EQ( info.Crc32, Crc32Of(want) )
                CHECK_EQ( info.Size, culngint(LEVEL_DATA_SIZE) )
                '' nivelul 0 stocheaza (metoda 0): dimensiunea comprimata e chiar dimensiunea
                if level = 0 then CHECK_EQ( info.CompressedSize, info.Size )
                if level > 0 andalso k = KindZero then CHECK_LT( info.CompressedSize * 100, info.Size )
                CHECK_EQ( r.ReadBytes(KindName(k) & ".bin", got), 0 )
                dim as integer diff = FirstDiff(got, want)
                CHECK_MSG( diff = -1, "primul octet diferit la " & diff )
            next
        next
    next
END_TEST_CASE

'' nivelurile mari comprima cel putin la fel de bine textul ca nivelul 1
TEST_CASE( Niveluri, NivelMareComprimaMaiBine )
    dim as string b1, b9, b10
    REQUIRE_EQ( LevelArchive(1, b1), 0 )
    REQUIRE_EQ( LevelArchive(9, b9), 0 )
    REQUIRE_EQ( LevelArchive(10, b10), 0 )
    CHECK_LE( CompSize(b9, KindText), CompSize(b1, KindText) )
    CHECK_LE( CompSize(b10, KindText), CompSize(b9, KindText) )
END_TEST_CASE

'' un nivel negativ inseamna nivelul implicit (6)
TEST_CASE( Niveluri, NegativInseamnaImplicit )
    dim as string b6
    REQUIRE_EQ( LevelArchive(ZIP_DEFAULT_COMPRESSION_LEVEL, b6), 0 )
    dim as long negs(...) = { -1, -6, -100, -2147483647 - 1 }
    for i as long = 0 to ubound(negs)
        TEST_CONTEXT( "nivel " & negs(i) )
        dim as string bn
        REQUIRE_EQ( LevelArchive(negs(i), bn), 0 )
        for k as long = KindZero to KindText
            CHECK_EQ( CompSize(bn, k), CompSize(b6, k) )
        next
    next
END_TEST_CASE

'' nivelurile de peste 10 sunt refuzate cu ZIP_EINVLVL, iar arhiva nu se creeaza
TEST_CASE( Niveluri, PestePlajaRefuzate )
    dim as ustring d = WorkDir()
    dim as long bad(...) = { 11, 12, 15, 16, 26, 255, 256, &h400, &h800, &h7FFFFFFF }
    for i as long = 0 to ubound(bad)
        TEST_CONTEXT( "nivel " & bad(i) & " (&h" & hex(bad(i)) & ")" )
        dim as ustring p = d & "\nivel_" & bad(i) & ".zip"
        dim as ZipArchive w
        CHECK_EQ( w.OpenFile(p, ZipWrite, bad(i)), ZIP_EINVLVL )
        CHECK_TRUE( w.IsOpen = false )
        w.Close()
        CHECK_MSG( FileExists(p) = false, "arhiva a fost creata" )
        dim as ZipArchive m
        CHECK_EQ( m.CreateInMemory(bad(i)), ZIP_EINVLVL )
        CHECK_TRUE( m.IsOpen = false )
    next
END_TEST_CASE

'' la citire nivelul nu conteaza: cautarea ramane fara majuscule si datele ies decomprimate
TEST_CASE( Niveluri, IgnoratLaCitire )
    dim as ustring p = WorkDir() & "\citire.zip"
    dim as ZipArchive w
    REQUIRE_EQ( w.OpenFile(p, ZipWrite), 0 )
    REQUIRE_EQ( w.AddText("a.txt", "continut continut continut"), 0 )
    w.Close()
    dim as long levels(...) = { 0, 9, 10, &h100, &h200, &h400 }
    for i as long = 0 to ubound(levels)
        TEST_CONTEXT( "nivel &h" & hex(levels(i)) )
        dim as ZipArchive r
        dim as long e = r.OpenFile(p, ZipRead, levels(i))
        '' acceptat (nivelul nu conteaza) sau refuzat ca nivel invalid; nu altceva
        CHECK_MSG( e = 0 orelse e = ZIP_EINVLVL, "OpenFile: " & e )
        if e <> 0 then continue for
        CHECK_TRUE( r.Contains("A.TXT") )
        dim as ustring t
        CHECK_EQ( r.ReadText("a.txt", t), 0 )
        dim as ustring wantT = "continut continut continut"
        CHECK_EQ( t, wantT )
    next
END_TEST_CASE

'' adaugarea cu alt nivel decat arhiva initiala: intrarile vechi raman citibile, cele noi la nivelul nou
TEST_CASE( Niveluri, AdaugareCuAltNivel )
    dim as ustring p = WorkDir() & "\mixt.zip"
    dim as string txt = MakeData(LEVEL_DATA_SIZE, KindText)
    dim as ZipArchive w
    REQUIRE_EQ( w.OpenFile(p, ZipWrite, 9), 0 )
    REQUIRE_EQ( w.AddBytes("nivel9.bin", txt), 0 )
    w.Close()
    dim as ZipArchive a
    REQUIRE_EQ( a.OpenFile(p, ZipAppend, 0), 0 )
    REQUIRE_EQ( a.AddBytes("nivel0.bin", txt), 0 )
    a.Close()
    REQUIRE_EQ( a.OpenFile(p, ZipAppend, 1), 0 )
    REQUIRE_EQ( a.AddBytes("nivel1.bin", txt), 0 )
    a.Close()

    dim as ZipArchive r
    REQUIRE_EQ( r.OpenFile(p), 0 )
    REQUIRE_EQ( r.Count, 3 )
    dim as ZipEntryInfo i9, i0, i1
    REQUIRE_EQ( r.FindEntry("nivel9.bin", i9), 0 )
    REQUIRE_EQ( r.FindEntry("nivel0.bin", i0), 0 )
    REQUIRE_EQ( r.FindEntry("nivel1.bin", i1), 0 )
    CHECK_EQ( i0.CompressedSize, i0.Size )
    CHECK_LT( i9.CompressedSize, i9.Size )
    CHECK_LT( i1.CompressedSize, i1.Size )
    for idx as long = 0 to 2
        TEST_CONTEXT( "index " & idx )
        dim as string got
        CHECK_EQ( r.ReadBytesAt(idx, got), 0 )
        CHECK_MSG( FirstDiff(got, txt) = -1, "continut diferit" )
    next
END_TEST_CASE

'' ================================================================== 3. citire pe bucati (nivelul 1)
'' zip_entry_noallocreadwithoffset si zip_entry_extract, pe opt arhive: fisier sau memorie, nivel 6
'' sau 0 (stocat), fara sau cu parola. Biblioteca are cod separat pentru parola si pentru memorie.

dim shared as string BIG_DATA, RAND_DATA, SMALL_DATA
BIG_DATA = MakeData(300007, KindText)
RAND_DATA = MakeData(200003, KindRandom, 777)
SMALL_DATA = MakeData(1000, KindRandom, 99)

type ReadCfg
    as boolean inFile
    as long level
    as string password
end type

function MakeCfg(byval c as long) as ReadCfg
    dim as ReadCfg r
    r.inFile = (c and 1) <> 0
    r.level = iif(c and 2, 0, 6)
    r.password = iif(c and 4, "secret-123", "")
    return r
end function

function CfgName(byref c as const ReadCfg) as string
    return iif(c.inFile, "fisier", "memorie") & ", nivel " & c.level & iif(len(c.password), ", cu parola", "")
end function

'' o arhiva deschisa la nivelul 1 pentru citire; se inchide singura
type Opened
    as zip_t ptr z
    as boolean mem
    as string bytes          '' bufferul unei arhive din memorie: biblioteca nu il copiaza
    declare destructor()
end type

destructor Opened()
    if z = 0 then exit destructor
    if mem then zip_stream_close(z) else zip_close(z)
end destructor

'' scrie arhiva configuratiei c (cu ZipArchive) si o deschide la nivelul 1
function OpenCfg(byref c as const ReadCfg, byref dir_ as const ustring, byref o as Opened) as boolean
    dim as ZipArchive w
    dim as ustring p = dir_ & "\bucati.zip"
    '' copie locala: FBC-Modern da error 181 la "end function" cand campul string al unui UDT
    '' primit byref const ajunge direct intr-un parametru byref const ustring
    dim as ustring pwU = c.password
    if c.inFile then
        if w.OpenFile(p, ZipWrite, c.level, pwU) <> 0 then return false
    else
        if w.CreateInMemory(c.level, pwU) <> 0 then return false
    end if
    if w.AddBytes("mare.bin", BIG_DATA) <> 0 then return false
    if w.AddBytes("aleator.bin", RAND_DATA) <> 0 then return false
    if w.AddBytes("mic.bin", SMALL_DATA) <> 0 then return false
    if w.AddBytes("gol.bin", "") <> 0 then return false
    if w.AddDirectory("dir") <> 0 then return false
    if c.inFile = false then
        if w.ToBytes(o.bytes) <> 0 then return false
    end if
    w.Close()

    dim as string pw8 = c.password, p8 = p
    o.mem = (c.inFile = false)
    if c.inFile andalso len(pw8) > 0 then
        o.z = zip_open_with_password(strptr(p8), 0, asc("r"), strptr(pw8))
    elseif c.inFile then
        o.z = zip_open(strptr(p8), 0, asc("r"))
    elseif len(pw8) > 0 then
        o.z = zip_stream_open_with_password(strptr(o.bytes), len(o.bytes), 0, asc("r"), strptr(pw8))
    else
        o.z = zip_stream_open(strptr(o.bytes), len(o.bytes), 0, asc("r"))
    end if
    return o.z <> 0
end function

'' zip_entry_noallocreadwithoffset intr-un buffer cu loc de ajuns; intoarce codul, datele in got
function ReadWindow(byval z as zip_t ptr, byval offset as uinteger, byval size as uinteger, _
        byval room as integer, byref got as string) as integer
    dim as string buf = string(room + 16, "~")
    dim as integer n = zip_entry_noallocreadwithoffset(z, offset, size, strptr(buf))
    got = iif(n > 0, left(buf, n), "")
    '' nimic scris dupa octetii raportati
    if n >= 0 andalso mid(buf, n + 1, 16) <> string(16, "~") then return -1000
    return n
end function

'' bucatile primite de apelul invers al lui zip_entry_extract
type Collector
    as string data_
    as long calls
    as boolean contiguous = true
    as long stopAtCall          '' > 0: la acest apel intoarce mai putin decat a primit
end type

function OnChunk cdecl(byval arg as any ptr, byval offset as ulongint, byval data_ as const any ptr, _
        byval size as uinteger) as uinteger
    dim as Collector ptr c = arg
    c->calls += 1
    if offset <> culngint(len(c->data_)) then c->contiguous = false
    if size > 0 then
        dim as integer at = len(c->data_)
        c->data_ &= space(size)
        memcpy(strptr(c->data_) + at, data_, size)
    end if
    if c->stopAtCall > 0 andalso c->calls >= c->stopAtCall then return iif(size > 0, size - 1, 1)
    return size
end function

'' ferestre la offseturi si dimensiuni alese pe granite; rezultatul e min(size, ce a ramas)
TEST_CASE( Bucati, FereastraLaOffset )
    dim as ustring d = WorkDir()
    for c as long = 0 to 7
        dim as ReadCfg cfg = MakeCfg(c)
        TEST_CONTEXT( CfgName(cfg) )
        dim as Opened o
        REQUIRE_TRUE( OpenCfg(cfg, d, o) )
        for e as long = 0 to 1
            dim as string nm = iif(e = 0, "mare.bin", "aleator.bin")
            dim as string want = iif(e = 0, BIG_DATA, RAND_DATA)
            dim as integer L = len(want)
            TEST_CONTEXT( nm )
            REQUIRE_EQ( zip_entry_open(o.z, nm), 0 )
            dim as integer offs(...) = { 0, 1, 32767, 32768, 65535, 65536, L \ 2, L - 2, L - 1 }
            dim as uinteger sizes(...) = { 0, 1, 100, 32768, 65536, L, &hFFFFFFFFFFFFFFFFull }
            for i as long = 0 to ubound(offs)
                for j as long = 0 to ubound(sizes)
                    dim as integer rest = L - offs(i)
                    dim as integer wantN = iif(sizes(j) < rest, sizes(j), rest)
                    dim as string got
                    dim as integer n = ReadWindow(o.z, offs(i), sizes(j), wantN, got)
                    CHECK_MSG( n = wantN, "offset " & offs(i) & ", size " & sizes(j) & ": " & n & ", asteptat " & wantN )
                    if n = wantN then CHECK_MSG( got = mid(want, offs(i) + 1, wantN), "offset " & offs(i) & ", size " & sizes(j) & ": date diferite" )
                next
            next
            zip_entry_close(o.z)
        next
    next
END_TEST_CASE

'' un offset la sau dupa capat e ZIP_EINVAL, si la intrarea goala
TEST_CASE( Bucati, DincoloDeCapat )
    dim as ustring d = WorkDir()
    for c as long = 0 to 7
        dim as ReadCfg cfg = MakeCfg(c)
        TEST_CONTEXT( CfgName(cfg) )
        dim as Opened o
        REQUIRE_TRUE( OpenCfg(cfg, d, o) )
        REQUIRE_EQ( zip_entry_open(o.z, "mic.bin"), 0 )
        dim as uinteger offs(...) = { 1000, 1001, &hFFFFFFFFull, &h100000000ull, &hFFFFFFFFFFFFFFFFull }
        for i as long = 0 to ubound(offs)
            dim as string got
            CHECK_MSG( ReadWindow(o.z, offs(i), 10, 10, got) = ZIP_EINVAL, "offset " & offs(i) )
        next
        zip_entry_close(o.z)
        REQUIRE_EQ( zip_entry_open(o.z, "gol.bin"), 0 )
        dim as string got
        CHECK_EQ( ReadWindow(o.z, 0, 10, 10, got), clngint(ZIP_EINVAL) )
        zip_entry_close(o.z)
    next
END_TEST_CASE

'' intrarea refacuta din bucati consecutive e identica cu originalul
TEST_CASE( Bucati, RefacereDinBucati )
    dim as ustring d = WorkDir()
    for c as long = 0 to 7
        dim as ReadCfg cfg = MakeCfg(c)
        TEST_CONTEXT( CfgName(cfg) )
        dim as Opened o
        REQUIRE_TRUE( OpenCfg(cfg, d, o) )
        for e as long = 0 to 1
            dim as string nm = iif(e = 0, "mic.bin", "mare.bin")
            dim as string want = iif(e = 0, SMALL_DATA, BIG_DATA)
            dim as integer chunks(1 to 3)
            if e = 0 then chunks(1) = 1 : chunks(2) = 7 : chunks(3) = 333 else chunks(1) = 4096 : chunks(2) = 65536 : chunks(3) = 100000
            REQUIRE_EQ( zip_entry_open(o.z, nm), 0 )
            for k as long = 1 to 3
                TEST_CONTEXT( nm & " in bucati de " & chunks(k) )
                dim as string all_, got
                dim as integer off = 0, n
                do while off < len(want)
                    n = ReadWindow(o.z, off, chunks(k), chunks(k), got)
                    if n <= 0 then exit do
                    all_ &= got
                    off += n
                loop
                CHECK_EQ( off, clngint(len(want)) )
                CHECK_MSG( FirstDiff(all_, want) = -1, "primul octet diferit la " & FirstDiff(all_, want) )
            next
            zip_entry_close(o.z)
        next
    next
END_TEST_CASE

'' fara intrare deschisa, pe un director si fara arhiva: coduri de eroare, nu date
TEST_CASE( Bucati, DirectorSiFaraIntrare )
    dim as ustring d = WorkDir()
    for c as long = 0 to 7
        dim as ReadCfg cfg = MakeCfg(c)
        TEST_CONTEXT( CfgName(cfg) )
        dim as Opened o
        REQUIRE_TRUE( OpenCfg(cfg, d, o) )
        dim as string got
        dim as Collector col
        CHECK_EQ( ReadWindow(o.z, 0, 10, 10, got), clngint(ZIP_ENOENT) )
        CHECK_EQ( zip_entry_extract(o.z, @OnChunk, @col), ZIP_ENOENT )
        REQUIRE_EQ( zip_entry_open(o.z, "dir/"), 0 )
        CHECK_EQ( zip_entry_isdir(o.z), 1 )
        CHECK_EQ( ReadWindow(o.z, 0, 10, 10, got), clngint(ZIP_EINVENTTYPE) )
        '' ca zip_entry_read, zip_entry_noallocread si zip_entry_fread
        CHECK_EQ( zip_entry_extract(o.z, @OnChunk, @col), ZIP_EINVENTTYPE )
        CHECK_EQ( col.calls, 0 )
        zip_entry_close(o.z)
    next
    dim as Collector col
    dim as string buf = space(10)
    CHECK_EQ( zip_entry_noallocreadwithoffset(0, 0, 10, strptr(buf)), clngint(ZIP_ENOINIT) )
    CHECK_EQ( zip_entry_extract(0, @OnChunk, @col), ZIP_ENOINIT )
END_TEST_CASE

'' zip_entry_extract da datele in ordine, cu offseturi consecutive, si exact cat are intrarea
TEST_CASE( Bucati, ExtractPeBucati )
    dim as ustring d = WorkDir()
    for c as long = 0 to 7
        dim as ReadCfg cfg = MakeCfg(c)
        TEST_CONTEXT( CfgName(cfg) )
        dim as Opened o
        REQUIRE_TRUE( OpenCfg(cfg, d, o) )
        dim as string names(...) = { "mare.bin", "aleator.bin", "mic.bin", "gol.bin" }
        for e as long = 0 to ubound(names)
            TEST_CONTEXT( names(e) )
            dim as string want
            select case e
            case 0 : want = BIG_DATA
            case 1 : want = RAND_DATA
            case 2 : want = SMALL_DATA
            end select
            REQUIRE_EQ( zip_entry_open(o.z, names(e)), 0 )
            dim as Collector col
            CHECK_EQ( zip_entry_extract(o.z, @OnChunk, @col), 0 )
            CHECK_TRUE( col.contiguous )
            CHECK_EQ( clngint(len(col.data_)), clngint(len(want)) )
            CHECK_MSG( FirstDiff(col.data_, want) = -1, "primul octet diferit la " & FirstDiff(col.data_, want) )
            CHECK_EQ( Crc32Of(col.data_), zip_entry_crc32(o.z) )
            TestLog( names(e) & ": " & col.calls & " apeluri" )
            zip_entry_close(o.z)
        next
    next
END_TEST_CASE

'' un apel invers care consuma mai putin decat a primit opreste extragerea cu eroare
TEST_CASE( Bucati, ExtractOprit )
    dim as ustring d = WorkDir()
    for c as long = 0 to 7
        dim as ReadCfg cfg = MakeCfg(c)
        TEST_CONTEXT( CfgName(cfg) )
        dim as Opened o
        REQUIRE_TRUE( OpenCfg(cfg, d, o) )
        REQUIRE_EQ( zip_entry_open(o.z, "mare.bin"), 0 )
        dim as Collector col
        col.stopAtCall = 1
        CHECK_LT( zip_entry_extract(o.z, @OnChunk, @col), 0 )
        CHECK_EQ( col.calls, 1 )
        zip_entry_close(o.z)
        '' intrarea se poate citi din nou, intreaga, dupa oprire
        REQUIRE_EQ( zip_entry_open(o.z, "mare.bin"), 0 )
        dim as Collector again
        CHECK_EQ( zip_entry_extract(o.z, @OnChunk, @again), 0 )
        CHECK_MSG( FirstDiff(again.data_, BIG_DATA) = -1, "a doua extragere difera" )
        zip_entry_close(o.z)
    next
END_TEST_CASE

'' ================================================================== 4. arhive stricate
'' Regula: o arhiva stricata fie e refuzata la deschidere, fie fiecare citire (nivelul 2 si nivelul 1)
'' intoarce o eroare sau exact datele originale. Niciodata date gresite fara eroare si niciun crash.

'' intrarile arhivelor mici de la acest grup, in ordinea adaugarii ("" pentru director)
dim shared as string CORRUPT_NAMES(0 to 3), CORRUPT_DATA(0 to 3)
CORRUPT_NAMES(0) = "a.txt" : CORRUPT_DATA(0) = MakeData(300, KindText)
CORRUPT_NAMES(1) = "b.bin" : CORRUPT_DATA(1) = MakeData(64, KindRandom, 4242)
CORRUPT_NAMES(2) = "gol.bin" : CORRUPT_DATA(2) = ""
CORRUPT_NAMES(3) = "c/" : CORRUPT_DATA(3) = ""

'' arhiva mica a variantei v: 0 = nivel 6, 1 = nivel 0 (stocat), 2 = nivel 6 cu parola
function CorruptPassword(byval v as long) as string
    return iif(v = 2, "parola-x", "")
end function

function CorruptVariant(byval v as long) as string
    return iif(v = 0, "nivel 6", iif(v = 1, "nivel 0", "cu parola"))
end function

function SmallArchive(byval v as long) as string
    dim as ZipArchive w
    dim as ustring pw = CorruptPassword(v)
    if w.CreateInMemory(iif(v = 1, 0, 6), pw) <> 0 then return ""
    for i as long = 0 to 2
        if w.AddBytes(CORRUPT_NAMES(i), CORRUPT_DATA(i)) <> 0 then return ""
    next
    if w.AddDirectory("c") <> 0 then return ""
    dim as string b
    if w.ToBytes(b) <> 0 then return ""
    return b
end function

'' citeste tot ce se poate din bytes, pe ambele niveluri; intoarce descrierea primei citiri care a dat
'' date gresite fara eroare ("" = nicio problema)
function SilentBadRead(byref bytes as const string, byref pw as const string) as string
    '' nivelul 2
    dim as ZipArchive r
    dim as ustring pwU = pw
    if r.OpenMemory(bytes, ZipRead, pwU) = 0 then
        dim as integer n = r.Count
        dim as ZipEntryInfo entries()
        r.ListEntries(entries())
        for i as long = 0 to iif(n < 4, n, 4) - 1
            dim as string got
            if r.ReadBytesAt(i, got) = 0 andalso got <> CORRUPT_DATA(i) then
                return "ReadBytesAt(" & i & "): " & len(got) & " octeti gresiti"
            end if
        next
    end if

    '' nivelul 1
    dim as string copy_ = bytes
    dim as zip_t ptr z
    if len(pw) then
        z = zip_stream_open_with_password(strptr(copy_), len(copy_), 0, asc("r"), strptr(pw))
    else
        z = zip_stream_open(strptr(copy_), len(copy_), 0, asc("r"))
    end if
    if z = 0 then return ""
    dim as string result
    dim as integer n = zip_entries_total(z)
    for i as long = 0 to iif(n < 4, n, 4) - 1
        if zip_entry_openbyindex(z, i) <> 0 then continue for
        dim as string want = CORRUPT_DATA(i)
        dim as any ptr buf = 0
        dim as uinteger size = 0
        dim as integer k = zip_entry_read(z, @buf, @size)
        if k >= 0 then
            dim as string got = space(size)
            if size > 0 then memcpy(strptr(got), buf, size)
            if got <> want andalso len(result) = 0 then result = "zip_entry_read(" & i & "): " & size & " octeti gresiti"
        end if
        if buf then deallocate(buf)
        dim as string win
        k = ReadWindow(z, 0, len(want) + 8, len(want) + 8, win)
        if k = -1000 andalso len(result) = 0 then result = "noallocreadwithoffset(" & i & "): scrie dupa capat"
        if k >= 0 andalso win <> left(want, k) andalso len(result) = 0 then result = "noallocreadwithoffset(" & i & "): date gresite"
        dim as Collector col
        if zip_entry_extract(z, @OnChunk, @col) = 0 andalso col.data_ <> want andalso len(result) = 0 then
            result = "zip_entry_extract(" & i & "): " & len(col.data_) & " octeti gresiti"
        end if
        zip_entry_close(z)
    next
    zip_stream_close(z)
    return result
end function

'' arhivele bune se citesc corect (altfel testele de mai jos nu spun nimic)
TEST_CASE( Stricate, ArhiveleBune )
    for v as long = 0 to 2
        TEST_CONTEXT( CorruptVariant(v) )
        dim as string b = SmallArchive(v)
        REQUIRE_GT( clngint(len(b)), 0ll )
        dim as ZipArchive r
        dim as ustring pw = CorruptPassword(v)
        REQUIRE_EQ( r.OpenMemory(b, ZipRead, pw), 0 )
        REQUIRE_EQ( r.Count, 4 )
        for i as long = 0 to 2
            dim as string got
            CHECK_EQ( r.ReadBytesAt(i, got), 0 )
            CHECK_TRUE( got = CORRUPT_DATA(i) )
        next
        dim as string bad = SilentBadRead(b, CorruptPassword(v))
        CHECK_MSG( bad = "", bad )
        '' verificarea insasi: cu alte date asteptate, SilentBadRead trebuie sa observe diferenta
        dim as string keep = CORRUPT_DATA(0)
        CORRUPT_DATA(0)[5] xor= 1
        CHECK_MSG( SilentBadRead(b, CorruptPassword(v)) <> "", "SilentBadRead nu vede date gresite" )
        CORRUPT_DATA(0) = keep
    next
END_TEST_CASE

'' orice prefix al arhivei (fara directorul central de la sfarsit) e refuzat la deschidere
TEST_CASE( Stricate, Trunchiate )
    dim as ustring d = WorkDir()
    for v as long = 0 to 2
        TEST_CONTEXT( CorruptVariant(v) )
        dim as string b = SmallArchive(v)
        dim as ustring pw = CorruptPassword(v)
        for L as integer = 0 to len(b) - 1
            dim as string part = left(b, L)
            dim as ZipArchive r
            dim as long e = r.OpenMemory(part, ZipRead, pw)
            CHECK_MSG( e < 0, "prefixul de " & L & " octeti din " & len(b) & " s-a deschis" )
            dim as string bad = SilentBadRead(part, CorruptPassword(v))
            CHECK_MSG( bad = "", "prefixul de " & L & ": " & bad )
            '' din fisier, pentru o parte din lungimi
            if L mod 17 = 0 orelse L >= len(b) - 30 then
                REQUIRE_TRUE( WriteAll(d & "\trunchiat.zip", part) )
                dim as ZipArchive f
                CHECK_MSG( f.OpenFile(d & "\trunchiat.zip", ZipRead, 0, pw) < 0, "fisierul trunchiat la " & L & " s-a deschis" )
            end if
        next
    next
END_TEST_CASE

'' fiecare octet schimbat, pe rand: eroare sau datele bune, nimic altceva
TEST_CASE( Stricate, OctetiSchimbati )
    dim as ubyte masks(...) = { &hFF, &h01, &h80 }
    for v as long = 0 to 2
        TEST_CONTEXT( CorruptVariant(v) )
        dim as string b = SmallArchive(v)
        dim as long problems = 0
        for p as integer = 0 to len(b) - 1
            for m as long = 0 to ubound(masks)
                dim as string x = b
                x[p] xor= masks(m)
                dim as string bad = SilentBadRead(x, CorruptPassword(v))
                if len(bad) then
                    problems += 1
                    if problems <= 10 then CHECK_MSG( false, "octetul " & p & " xor &h" & hex(masks(m)) & ": " & bad )
                end if
            next
        next
        CHECK_MSG( problems = 0, problems & " modificari au dat date gresite fara eroare" )
    next
END_TEST_CASE

'' CRC-ul gresit in directorul central: fiecare cale de citire si extragere da eroare
TEST_CASE( Stricate, CrcGresit )
    dim as ustring d = WorkDir()
    for v as long = 0 to 2
        TEST_CONTEXT( CorruptVariant(v) )
        dim as string b = SmallArchive(v)
        '' antetul din directorul central al primei intrari; CRC-ul e la +16
        dim as integer cd = instr(b, "PK" & chr(1, 2))
        REQUIRE_TRUE( cd > 0 )
        b[cd - 1 + 16] xor= &h5A
        dim as ustring pw = CorruptPassword(v)
        dim as ZipArchive r
        REQUIRE_EQ( r.OpenMemory(b, ZipRead, pw), 0 )
        dim as string got
        CHECK_LT( r.ReadBytes("a.txt", got), 0 )
        '' ExtractEntry esuat nu lasa in urma un fisier nou cu date netestate
        dim as ustring target = d & "\a_" & v & ".txt"
        CHECK_LT( r.ExtractEntry("a.txt", target), 0 )
        CHECK_MSG( FileExists(target) = false, "fisierul nou a ramas pe disc" )
        '' un fisier care exista nu se sterge
        dim as ustring old_ = d & "\vechi_" & v & ".txt"
        REQUIRE_TRUE( WriteAll(old_, "vechi") )
        CHECK_LT( r.ExtractEntry("a.txt", old_), 0 )
        CHECK_TRUE( FileExists(old_) )
        '' o intrare buna se extrage in continuare
        dim as ustring okPath = d & "\b_" & v & ".bin"
        CHECK_EQ( r.ExtractEntry("b.bin", okPath), 0 )
        CHECK_TRUE( ReadAll(okPath) = CORRUPT_DATA(1) )
        dim as string bad = SilentBadRead(b, CorruptPassword(v))
        CHECK_MSG( bad = "", bad )
        dim as ustring dx = d & "\tot_" & v
        CreateDirectoryW(dx, 0)
        '' ExtractAll nu primeste parola
        if v <> 2 then
            CHECK_LT( ZipArchive.ExtractAllFromMemory(b, dx), 0 )
            dim as ustring pz = d & "\crc_" & v & ".zip"
            REQUIRE_TRUE( WriteAll(pz, b) )
            CHECK_LT( ZipArchive.ExtractAll(pz, dx), 0 )
        end if
    next
END_TEST_CASE

'' date care nu sunt arhive zip
TEST_CASE( Stricate, NuSuntArhive )
    dim as ustring d = WorkDir()
    dim as string eocd = "PK" & chr(5, 6) & string(18, 0)                 '' arhiva goala corecta
    dim as string eocd1 = "PK" & chr(5, 6) & string(4, 0) & chr(1, 0, 1, 0) & mkl(46) & mkl(1000) & chr(0, 0)
    dim as string cases(...) = { "PK", "PK" & chr(3, 4), "PK" & chr(5, 6), MakeData(1000, KindRandom, 5), _
        MakeData(1000, KindText), eocd1, string(4096, 0) }
    for i as long = 0 to ubound(cases)
        TEST_CONTEXT( "cazul " & i & " (" & len(cases(i)) & " octeti)" )
        dim as ZipArchive r
        CHECK_LT( r.OpenMemory(cases(i)), 0 )
        CHECK_TRUE( r.IsOpen = false )
        REQUIRE_TRUE( WriteAll(d & "\nu.zip", cases(i)) )
        dim as ZipArchive f
        CHECK_LT( f.OpenFile(d & "\nu.zip"), 0 )
        dim as string bad = SilentBadRead(cases(i), "")
        CHECK_MSG( bad = "", bad )
    next
    '' arhiva goala (doar sfarsitul directorului central) e corecta: 0 intrari
    dim as ZipArchive g
    CHECK_EQ( g.OpenMemory(eocd), 0 )
    CHECK_EQ( g.Count, 0 )
    REQUIRE_TRUE( WriteAll(d & "\gol.zip", eocd) )
    dim as ZipArchive gf
    CHECK_EQ( gf.OpenFile(d & "\gol.zip"), 0 )
    CHECK_EQ( gf.Count, 0 )
    '' fisier gol si director in loc de arhiva
    REQUIRE_TRUE( WriteAll(d & "\zero.zip", "") )
    dim as ZipArchive z0
    CHECK_LT( z0.OpenFile(d & "\zero.zip"), 0 )
    dim as ZipArchive zd
    CHECK_LT( zd.OpenFile(d), 0 )
    CHECK_TRUE( zd.IsOpen = false )
END_TEST_CASE

'' ================================================================== 5. nume de intrari

'' numele din directorul central, ca octeti, si flag-urile lor (bitul 11 = nume UTF-8)
sub CentralNames(byref bytes as const string, names() as string, flags() as long)
    erase names, flags
    dim as integer n = 0, p = instr(bytes, "PK" & chr(1, 2))
    while p > 0 andalso p + 45 <= len(bytes)
        dim as long nl = bytes[p - 1 + 28] or (bytes[p - 1 + 29] shl 8)
        redim preserve names(0 to n), flags(0 to n)
        flags(n) = bytes[p - 1 + 8] or (bytes[p - 1 + 9] shl 8)
        names(n) = mid(bytes, p + 46, nl)
        n += 1
        p = instr(p + 46 + nl, bytes, "PK" & chr(1, 2))
    wend
end sub

'' arhiva in memorie cu intrarile date (nume, continut = numele in UTF-8)
function NamedArchive(names() as ustring, byref bytes as string) as long
    dim as ZipArchive w
    dim as long e = w.CreateInMemory()
    if e <> 0 then return e
    for i as integer = lbound(names) to ubound(names)
        dim as string content = names(i)
        e = w.AddBytes(names(i), content)
        if e <> 0 then return e
    next
    return w.ToBytes(bytes)
end function

dim shared as ustring U_A, U_I, U_S, U_T, U_EMOJI, U_CJK, U_EURO
U_A = wchr(&h103) : U_I = wchr(&hEE) : U_S = wchr(&h219) : U_T = wchr(&h21B)
U_EMOJI = wchr(&hD83D, &hDE00)          '' U+1F600, in afara BMP (pereche de surogate in UTF-16)
U_CJK = wchr(&h6587, &h4EF6)            '' doua caractere CJK
U_EURO = wchr(&h20AC)

'' numele Unicode (diacritice, CJK, caractere in afara BMP) ies la fel cum au intrat
TEST_CASE( Nume, Unicode )
    dim as ustring names(...) = { "rom" & U_A & "n" & U_A & "/" & U_S & U_T & U_I & ".txt", U_CJK & ".txt", _
        "fata " & U_EMOJI & ".txt", U_EMOJI & U_EMOJI & "/" & U_EURO & U_EMOJI, "ascii.txt" }
    dim as string bytes
    REQUIRE_EQ( NamedArchive(names(), bytes), 0 )
    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    REQUIRE_EQ( r.Count, clngint(ubound(names) + 1) )
    for i as long = 0 to ubound(names)
        TEST_CONTEXT( "intrarea " & i )
        dim as string want8 = names(i)
        dim as ZipEntryInfo info
        REQUIRE_EQ( r.GetEntry(i, info), 0 )
        CHECK_EQ( info.Name, names(i) )
        dim as string got8 = info.Name
        CHECK_TRUE( got8 = want8 )
        CHECK_TRUE( r.Contains(names(i)) )
        dim as string data_
        CHECK_EQ( r.ReadBytes(names(i), data_), 0 )
        CHECK_TRUE( data_ = want8 )
    next
    '' UTF-8 corect: U+1F600 e F0 9F 98 80, nu doua surogate codate separat (CESU-8)
    dim as string emoji8 = U_EMOJI
    CHECK_EQ( emoji8, chr(&hF0, &h9F, &h98, &h80) )
END_TEST_CASE

'' numele non-ASCII au bitul 11 (UTF-8) in directorul central, ca alte programe sa le citeasca corect
TEST_CASE( Nume, FlagUtf8 )
    dim as ustring names(...) = { "ascii.txt", "rom" & U_A & "n" & U_A & ".txt", U_EMOJI & ".txt" }
    dim as string bytes
    REQUIRE_EQ( NamedArchive(names(), bytes), 0 )
    dim as string cn()
    dim as long fl()
    CentralNames(bytes, cn(), fl())
    REQUIRE_EQ( clngint(ubound(cn) + 1), 3ll )
    for i as long = 0 to 2
        TEST_CONTEXT( "intrarea " & i )
        dim as string want8 = names(i)
        CHECK_TRUE( cn(i) = want8 )
        if i > 0 then CHECK_MSG( (fl(i) and &h800) <> 0, "flag-uri &h" & hex(fl(i)) & ": lipseste bitul UTF-8" )
    next
END_TEST_CASE

'' numele are cel mult 65535 de octeti UTF-8 (campul de 16 biti din antet)
TEST_CASE( Nume, Lungime )
    dim as long lens(...) = { 1, 255, 256, 1000, 65534, 65535 }
    for i as long = 0 to ubound(lens)
        TEST_CONTEXT( "lungime " & lens(i) )
        dim as ustring names(0 to 0)
        names(0) = string(lens(i), "n")
        dim as string bytes
        REQUIRE_EQ( NamedArchive(names(), bytes), 0 )
        dim as ZipArchive r
        REQUIRE_EQ( r.OpenMemory(bytes), 0 )
        dim as ZipEntryInfo info
        REQUIRE_EQ( r.GetEntry(0, info), 0 )
        CHECK_EQ( clngint(len(info.Name)), clngint(lens(i)) )
        CHECK_TRUE( r.Contains(names(0)) )
    next
    '' 65536 de octeti: refuzat, iar arhiva ramane utilizabila
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    CHECK_EQ( w.AddBytes(string(65536, "n"), "x"), ZIP_EINVENTNAME )
    '' limita e in octeti: 32767 de "a" (2 octeti fiecare) incap, 32768 nu
    dim as ustring lungA, preaLungA
    for k as long = 1 to 32767
        lungA &= U_A
    next
    preaLungA = lungA & U_A
    CHECK_EQ( w.AddBytes(lungA, "x"), 0 )
    CHECK_EQ( w.AddBytes(preaLungA, "x"), ZIP_EINVENTNAME )
    CHECK_EQ( w.AddBytes("dupa.txt", "y"), 0 )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    CHECK_EQ( r.Count, 2 )
    CHECK_TRUE( r.Contains(lungA) )
    CHECK_TRUE( r.Contains("dupa.txt") )
END_TEST_CASE

'' "\" se scrie ca "/"; cautarea cu "\" gaseste aceeasi intrare
TEST_CASE( Nume, Backslash )
    dim as ustring names(...) = { "x\y.txt", "a\b\c.txt" }
    dim as string bytes
    REQUIRE_EQ( NamedArchive(names(), bytes), 0 )
    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    dim as ZipEntryInfo info
    REQUIRE_EQ( r.GetEntry(0, info), 0 )
    dim as ustring w0 = "x/y.txt"
    CHECK_EQ( info.Name, w0 )
    CHECK_TRUE( r.Contains("x/y.txt") )
    CHECK_TRUE( r.Contains("a/b/c.txt") )
    CHECK_TRUE( r.Contains("x\y.txt") )
    CHECK_TRUE( r.Contains("a\b\c.txt") )
    dim as string got
    CHECK_EQ( r.ReadBytes("a\b\c.txt", got), 0 )
    '' stergerea cu "\" sterge intrarea scrisa cu "/"
    dim as ZipArchive dz
    REQUIRE_EQ( dz.OpenMemory(bytes, ZipDelete), 0 )
    dim as ustring del(0 to 0)
    del(0) = "a\b\c.txt"
    CHECK_EQ( dz.DeleteEntries(del()), 1 )
    dim as string after
    REQUIRE_EQ( dz.ToBytes(after), 0 )
    dim as ZipArchive ra
    REQUIRE_EQ( ra.OpenMemory(after), 0 )
    CHECK_EQ( ra.Count, 1 )
    CHECK_TRUE( ra.Contains("x/y.txt") )
END_TEST_CASE

'' nume care difera doar prin majuscule: cautarea normala gaseste ultima, cea exacta (nivelul 1) pe fiecare
TEST_CASE( Nume, Majuscule )
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_EQ( w.AddBytes("Mare.txt", "1"), 0 )
    REQUIRE_EQ( w.AddBytes("mare.txt", "2"), 0 )
    REQUIRE_EQ( w.AddBytes("MARE.TXT", "3"), 0 )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    CHECK_EQ( r.Count, 3 )
    dim as string got
    '' la mai multe potriviri, cautarea fara majuscule gaseste ultima intrare (ca la Duplicate);
    '' numele scris exact nu are prioritate
    CHECK_EQ( r.ReadBytes("mArE.tXt", got), 0 )
    CHECK_EQ( got, "3" )
    CHECK_EQ( r.ReadBytes("mare.txt", got), 0 )
    TestLog( "ReadBytes(""mare.txt"") gaseste: " & got )
    dim as zip_t ptr z = zip_stream_open(strptr(bytes), len(bytes), 0, asc("r"))
    REQUIRE_TRUE( z <> 0 )
    dim as string exact(...) = { "Mare.txt", "mare.txt", "MARE.TXT" }
    for i as long = 0 to 2
        TEST_CONTEXT( exact(i) )
        CHECK_EQ( zip_entry_opencasesensitive(z, exact(i)), 0 )
        CHECK_EQ( zip_entry_index(z), clngint(i) )
        zip_entry_close(z)
    next
    CHECK_EQ( zip_entry_opencasesensitive(z, "mArE.tXt"), ZIP_ENOENT )
    zip_stream_close(z)
    '' stergerea tine cont de majuscule: sterge doar numele scris exact
    dim as ZipArchive dz
    REQUIRE_EQ( dz.OpenMemory(bytes, ZipDelete), 0 )
    dim as ustring del(0 to 0)
    del(0) = "mArE.tXt"
    CHECK_EQ( dz.DeleteEntries(del()), 0 )
    del(0) = "mare.txt"
    CHECK_EQ( dz.DeleteEntries(del()), 1 )
    dim as string after
    REQUIRE_EQ( dz.ToBytes(after), 0 )
    dim as ZipArchive ra
    REQUIRE_EQ( ra.OpenMemory(after), 0 )
    CHECK_EQ( ra.Count, 2 )
END_TEST_CASE

'' acelasi nume de doua ori: ambele intrari exista, cautarea o gaseste pe ultima
TEST_CASE( Nume, Duplicate )
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_EQ( w.AddBytes("dublu.txt", "primul"), 0 )
    dim as long e2 = w.AddBytes("dublu.txt", "al doilea")
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    TestLog( "a doua adaugare: " & e2 & ", intrari: " & r.Count )
    if e2 = 0 then
        CHECK_EQ( r.Count, 2 )
        dim as string a, b, f
        CHECK_EQ( r.ReadBytesAt(0, a), 0 )
        CHECK_EQ( r.ReadBytesAt(1, b), 0 )
        CHECK_EQ( a, "primul" )
        CHECK_EQ( b, "al doilea" )
        CHECK_EQ( r.ReadBytes("dublu.txt", f), 0 )
        '' ultima intrare cu acel nume, ca la dezarhivatoarele obisnuite
        CHECK_EQ( f, b )
        TestLog( "ReadBytes gaseste: " & f )
    else
        CHECK_EQ( r.Count, 1 )
    end if
END_TEST_CASE

'' directoare: "d", "d/" si "x\y" dau o singura bara la sfarsit
TEST_CASE( Nume, Directoare )
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_EQ( w.AddDirectory("d"), 0 )
    REQUIRE_EQ( w.AddDirectory("e/"), 0 )
    REQUIRE_EQ( w.AddDirectory("x\y"), 0 )
    REQUIRE_EQ( w.AddDirectory("p\q\"), 0 )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    dim as ustring want(...) = { "d/", "e/", "x/y/", "p/q/" }
    REQUIRE_EQ( r.Count, 4 )
    for i as long = 0 to 3
        TEST_CONTEXT( want(i) )
        dim as ZipEntryInfo info
        REQUIRE_EQ( r.GetEntry(i, info), 0 )
        CHECK_EQ( info.Name, want(i) )
        CHECK_TRUE( info.IsDirectory )
    next
END_TEST_CASE

'' nume neobisnuite, dar scrise in arhiva: se citesc inapoi exact (extragerea lor e la grupul 6)
TEST_CASE( Nume, Neobisnuite )
    dim as ustring names(...) = { " spatiu la capete ", "tab" & chr(9) & ".txt", "ctrl" & chr(1) & ".txt", _
        "a:b.txt", "stea*?<>|.txt", "/radacina.txt", "C:\disc.txt", "..", ".", "...", "punct.", "a//b.txt" }
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    dim as long added = 0
    for i as long = 0 to ubound(names)
        TEST_CONTEXT( "nume " & i )
        dim as string content = names(i)
        dim as long e = w.AddBytes(names(i), content)
        CHECK_MSG( e = 0 orelse e = ZIP_EINVENTNAME, "AddBytes: " & e )
        if e = 0 then added += 1 else TestLog( "refuzat: nume " & i )
    next
    CHECK_EQ( w.AddBytes("", "x"), ZIP_EINVENTNAME )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    dim as ZipArchive r
    REQUIRE_EQ( r.OpenMemory(bytes), 0 )
    CHECK_EQ( r.Count, clngint(added) )
    for i as long = 0 to r.Count - 1
        TEST_CONTEXT( "intrarea " & i )
        dim as ZipEntryInfo info
        REQUIRE_EQ( r.GetEntry(i, info), 0 )
        dim as string got, name8 = info.Name
        if info.IsDirectory = false then
            CHECK_EQ( r.ReadBytesAt(i, got), 0 )
            '' continutul e numele original; "\" a devenit "/" in nume
            dim as string slashed = got
            for k as integer = 0 to len(slashed) - 1
                if slashed[k] = asc("\") then slashed[k] = asc("/")
            next
            CHECK_EQ( name8, slashed )
        end if
    next
END_TEST_CASE

'' ================================================================== 6. extragere periculoasa
'' Destinatia sta in <lucru>\cutie\d1\d2. Regula: extragerea nu scrie nimic in afara destinatiei, iar
'' o intrare fie da eroare, fie devine un fisier vizibil in destinatie, cu datele ei. Biblioteca se
'' opreste la prima eroare, deci fiecare nume riscant are arhiva lui.

'' toate fisierele de sub dir_ (cai complete), recursiv
sub ListFiles(byref dir_ as const ustring, files() as ustring)
    dim as WIN32_FIND_DATAW fd
    dim as HANDLE h = FindFirstFileW(dir_ & "\*", @fd)
    if h = INVALID_HANDLE_VALUE then exit sub
    do
        dim as ustring n = fd.cFileName
        if n <> "." andalso n <> ".." then
            dim as ustring full = dir_ & "\" & n
            if fd.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY then
                ListFiles(full, files())
            else
                dim as integer k = ubound(files) + 1
                redim preserve files(0 to k)
                files(k) = full
            end if
        end if
    loop while FindNextFileW(h, @fd)
    FindClose(h)
end sub

'' o cutie goala cu destinatia in ea; intoarce destinatia
function SandboxDest(byref work as const ustring, byref tag as const string) as ustring
    dim as ustring box = work & "\cutie_" & tag
    CreateDirectoryW(box, 0)
    ClearDir(box)
    CreateDirectoryW(box & "\d1", 0)
    CreateDirectoryW(box & "\d1\d2", 0)
    return box & "\d1\d2"
end function

'' fisierele scrise in afara destinatiei (in cutie, langa ea)
function Escaped(byref dest as const ustring) as string
    dim as ustring box = left(dest, len(dest) - len("\d1\d2"))
    dim as ustring files()
    ListFiles(box, files())
    dim as string r
    for i as integer = 0 to ubound(files)
        if left(files(i), len(dest) + 1) <> dest & "\" then
            dim as string f8 = mid(files(i), len(box) + 2)
            r &= " " & f8
        end if
    next
    return r
end function

'' arhiva cu o singura intrare, numele dat si continutul = numele (UTF-8)
function OneEntryArchive(byref name_ as const ustring) as string
    dim as ZipArchive w
    if w.CreateInMemory() <> 0 then return ""
    dim as string content = name_
    if w.AddBytes(name_, content) <> 0 then return ""
    dim as string b
    w.ToBytes(b)
    return b
end function

'' extrage arhiva din fisier (zip_extract) si din memorie (zip_stream_extract), fiecare in cutia ei;
'' verifica regula pentru intrarea unica cu numele name_; intoarce o problema sau ""
function ExtractOneChecked(byref work as const ustring, byref name_ as const ustring, byref tag as const string, _
        byref codes as string) as string
    dim as string bytes = OneEntryArchive(name_)
    if len(bytes) = 0 then return "arhiva nu s-a putut scrie"
    dim as string content = name_
    for how as long = 0 to 1
        dim as ustring dest = SandboxDest(work, tag & "_" & how)
        dim as long e
        if how = 0 then
            dim as ustring zp = work & "\arhiva_" & tag & ".zip"
            if WriteAll(zp, bytes) = false then return "nu pot scrie arhiva"
            e = ZipArchive.ExtractAll(zp, dest)
        else
            e = ZipArchive.ExtractAllFromMemory(bytes, dest)
        end if
        codes &= iif(how = 0, "fisier ", ", memorie ") & e
        dim as string esc = Escaped(dest)
        if len(esc) then return iif(how = 0, "fisier", "memorie") & ": scris in afara destinatiei:" & esc
        if e = 0 then
            '' un fisier vizibil in destinatie, cu datele intrarii
            dim as ustring files()
            ListFiles(dest, files())
            dim as boolean found = false
            for i as integer = 0 to ubound(files)
                if ReadAll(files(i)) = content then found = true
            next
            if found = false then
                return iif(how = 0, "fisier", "memorie") & ": extragere reusita, dar datele nu sunt in niciun fisier vizibil (" _
                    & (ubound(files) + 1) & " fisiere)"
            end if
        end if
    next
    return ""
end function

'' ".." in orice pozitie nu urca deasupra destinatiei
TEST_CASE( Extragere, UrcareCuPuncte )
    dim as ustring d = WorkDir()
    dim as ustring names(...) = { "../sus1.txt", "../../sus2.txt", "a/../../sus3.txt", "..\..\sus4.txt", _
        "./../sus5.txt", "a/b/../../../sus6.txt", "../d2/../../sus7.txt", "a/./../.././sus8.txt" }
    for i as long = 0 to ubound(names)
        dim as string n8 = names(i)
        TEST_CONTEXT( n8 )
        dim as string codes
        dim as string bad = ExtractOneChecked(d, names(i), "u" & i, codes)
        CHECK_MSG( bad = "", bad )
        TestLog( n8 & ": " & codes )
    next
END_TEST_CASE

'' o cale absoluta din arhiva ramane sub destinatie sau e refuzata
TEST_CASE( Extragere, CaleAbsoluta )
    dim as ustring d = WorkDir()
    '' calea absoluta a cutiei insesi: daca ar fi respectata, fisierul ar aparea langa destinatie
    dim as ustring boxAbs = d & "\cutie_a"
    dim as ustring slashAbs = boxAbs
    for k as integer = 0 to len(slashAbs) - 1
        if slashAbs[k] = asc("\") then slashAbs[k] = asc("/")
    next
    dim as ustring names(...) = { "/abs1.txt", "//abs2.txt", "\abs3.txt", boxAbs & "_0\abs4.txt", _
        slashAbs & "_0/abs5.txt", "\\?\" & boxAbs & "_0\abs6.txt", "\\localhost\" & mid(boxAbs, 1, 1) & "$" & mid(boxAbs, 3) & "_0\abs7.txt" }
    for i as long = 0 to ubound(names)
        dim as string n8 = names(i)
        TEST_CONTEXT( n8 )
        dim as string codes
        '' toate in aceeasi cutie "a", ca boxAbs sa fie cutia folosita
        dim as string bad = ExtractOneChecked(d, names(i), "a", codes)
        CHECK_MSG( bad = "", bad )
        TestLog( n8 & ": " & codes )
    next
END_TEST_CASE

'' nume pe care Windows le trateaza special: dispozitive, ":" (flux NTFS), punct si spatiu la final,
'' caractere interzise. Nicio intrare nu se pierde fara eroare; ":" si numele de dispozitiv sunt
'' refuzate cu ZIP_EINVENTNAME (altfel datele ajungeau in fluxul ascuns sau in dispozitiv)
TEST_CASE( Extragere, NumeWindows )
    dim as ustring d = WorkDir()
    dim as ustring names(...) = { "nul", "NUL.txt", "con", "aux.txt", "dir/nul", "COM1", "lpt9.bin", _
        "flux:ascuns.txt", "C:relativ.txt", "punct.", "spatiu ", "mai<mic.txt", "intrebare?.txt", _
        "ghilimele"".txt", "bara|.txt", "consola.txt", "nul_nu.txt" }
    '' primele 9 sunt refuzate
    const REFUSED = 9
    for i as long = 0 to ubound(names)
        dim as string n8 = names(i)
        TEST_CONTEXT( n8 )
        dim as string codes
        dim as string bad = ExtractOneChecked(d, names(i), "w" & i, codes)
        CHECK_MSG( bad = "", bad )
        if i < REFUSED then
            CHECK_EQ( codes, "fisier " & ZIP_EINVENTNAME & ", memorie " & ZIP_EINVENTNAME )
        end if
        TestLog( n8 & ": " & codes )
    next
END_TEST_CASE

'' nume care pe NTFS sunt acelasi fisier: al doilea il suprascrie pe primul, fara eroare
TEST_CASE( Extragere, AcelasiFisier )
    dim as ustring d = WorkDir()
    dim as ustring dest = SandboxDest(d, "s")
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_EQ( w.AddBytes("Mare.txt", "1"), 0 )
    REQUIRE_EQ( w.AddBytes("mare.txt", "2"), 0 )
    REQUIRE_EQ( w.AddBytes("x.txt", "3"), 0 )
    REQUIRE_EQ( w.AddBytes("x.txt", "4"), 0 )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    CHECK_EQ( ZipArchive.ExtractAllFromMemory(bytes, dest), 0 )
    dim as ustring files()
    ListFiles(dest, files())
    CHECK_EQ( clngint(ubound(files) + 1), 2ll )
    CHECK_EQ( ReadAll(dest & "\mare.txt"), "2" )
    CHECK_EQ( ReadAll(dest & "\x.txt"), "4" )
    CHECK_EQ( Escaped(dest), "" )
END_TEST_CASE

'' un fisier si apoi un director cu acelasi nume: eroare, iar fisierul ramane neatins
TEST_CASE( Extragere, FisierApoiDirector )
    dim as ustring d = WorkDir()
    dim as ustring dest = SandboxDest(d, "f")
    dim as ZipArchive w
    REQUIRE_EQ( w.CreateInMemory(), 0 )
    REQUIRE_EQ( w.AddBytes("x", "fisier"), 0 )
    REQUIRE_EQ( w.AddBytes("x/y.txt", "sub"), 0 )
    dim as string bytes
    REQUIRE_EQ( w.ToBytes(bytes), 0 )
    CHECK_LT( ZipArchive.ExtractAllFromMemory(bytes, dest), 0 )
    CHECK_EQ( ReadAll(dest & "\x"), "fisier" )
    CHECK_EQ( Escaped(dest), "" )
    '' invers: director, apoi fisier cu acelasi nume
    dim as ustring dest2 = SandboxDest(d, "g")
    dim as ZipArchive w2
    REQUIRE_EQ( w2.CreateInMemory(), 0 )
    REQUIRE_EQ( w2.AddDirectory("x"), 0 )
    REQUIRE_EQ( w2.AddBytes("x", "fisier"), 0 )
    REQUIRE_EQ( w2.ToBytes(bytes), 0 )
    CHECK_LT( ZipArchive.ExtractAllFromMemory(bytes, dest2), 0 )
    CHECK_EQ( Escaped(dest2), "" )
END_TEST_CASE

'' calea finala peste 260 de caractere: eroare sau fisierul complet (citit prin \\?\)
TEST_CASE( Extragere, CaleLunga )
    dim as ustring d = WorkDir()
    dim as ustring dest = SandboxDest(d, "l")
    dim as ustring name_ = string(100, "a") & "/" & string(100, "b") & "/" & string(100, "c") & ".txt"
    dim as string bytes = OneEntryArchive(name_)
    REQUIRE_TRUE( len(bytes) > 0 )
    dim as long e = ZipArchive.ExtractAllFromMemory(bytes, dest)
    TestLog( "ExtractAllFromMemory: " & e & ", lungimea caii: " & len(dest) + 1 + len(name_) )
    if e = 0 then
        dim as ustring full = "\\?\" & dest & "\" & string(100, "a") & "\" & string(100, "b") & "\" & string(100, "c") & ".txt"
        dim as string want = name_
        CHECK_TRUE( ReadAll(full) = want )
    end if
    CHECK_EQ( Escaped(dest), "" )
END_TEST_CASE

end TestKitMain( )
