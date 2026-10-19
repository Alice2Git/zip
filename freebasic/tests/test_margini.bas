'' test_margini.bas - marginile legaturii FreeBASIC cu TestKit, dincolo de test_c si test_fb:
'' dimensiuni de date si CRC calculat independent, niveluri de compresie, citire pe bucati (nivelul 1).
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

end TestKitMain( )
