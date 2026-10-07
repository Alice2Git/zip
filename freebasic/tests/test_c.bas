'' test_c.bas - nivelul 1 (zip_c.bi): fiecare grup de functii din zip.h, apelat direct.
''
''   test_c.exe <director_iesire>
''
'' Fiecare rulare lucreaza intr-un subdirector nou (c_<data>_<ora>[_n]) al directorului de iesire.

#include once "zip_c.bi"
#include once "crt/stdlib.bi"
#include once "crt/string.bi"

dim shared as long checks, failures

sub Check(byval ok as boolean, byref what as const string)
    checks += 1
    if ok = false then
        failures += 1
        print "  ESEC: " & what
    end if
end sub

'' director nou pentru rularea curenta
function NewRunDir(byref parent as const string, byref prefix as const string) as string
    dim as string d = date, t = time
    dim as string base_ = parent & "\" & prefix & mid(d, 7, 4) & mid(d, 1, 2) & mid(d, 4, 2) & "_" _
        & mid(t, 1, 2) & mid(t, 4, 2) & mid(t, 7, 2)
    dim as string dir_ = base_
    dim as long n = 1
    mkdir parent
    while mkdir(dir_) <> 0
        n += 1
        dir_ = base_ & "_" & n
        if n > 100 then return ""
    wend
    return dir_
end function

function ReadFileBytes(byref path as const string) as string
    dim as long f = freefile
    if open(path for binary access read as #f) <> 0 then return ""
    dim as string s = space(lof(f))
    if len(s) > 0 then get #f, , s
    close #f
    return s
end function

sub WriteFileBytes(byref path as const string, byref s as const string)
    dim as long f = freefile
    if open(path for binary access write as #f) = 0 then
        put #f, , s
        close #f
    end if
end sub

'' zip_entry_extract: aduna datele intr-un STRING
function CollectCallback cdecl(byval arg as any ptr, byval offset as ulongint, _
        byval data_ as const any ptr, byval size as uinteger) as uinteger
    dim as string ptr s = arg
    dim as string piece = space(size)
    if size > 0 then memcpy(strptr(piece), data_, size)
    *s &= piece
    return size
end function

'' zip_extract: numara fisierele; arg <> 0 opreste dupa primul
function CountCallback cdecl(byval filename as const zstring ptr, byval arg as any ptr) as long
    dim as long ptr n = arg
    n[0] += 1
    if n[1] <> 0 then return -1
    return 0
end function

dim as string outRoot = command(1)
if len(outRoot) = 0 then outRoot = exepath & "\out"
dim as string W = NewRunDir(outRoot, "c_")
if len(W) = 0 then
    print "nu pot crea directorul de lucru in " & outRoot
    end 2
end if
print "test_c: " & W

dim as string hello = "hello"
dim as string utf8Name = "fi" & chr(&hC8, &h99) & "ier.txt"   '' "fișier.txt" in UTF-8
dim as string bin256 = space(256)
for i as long = 0 to 255
    bin256[i] = i
next

'' ---- zip_strerror
Check(*zip_strerror(ZIP_ENOENT) = "entry not found", "zip_strerror(ZIP_ENOENT)")
Check(zip_strerror(-1000) = 0, "zip_strerror(cod necunoscut) = NULL")

'' ---- scriere in fisier
dim as string zipPath = W & "\a.zip"
scope
    dim as zip_t ptr z = zip_open(zipPath, ZIP_DEFAULT_COMPRESSION_LEVEL, asc("w"))
    Check(z <> 0, "zip_open w")
    Check(zip_entry_open(z, "a.txt") = 0, "zip_entry_open a.txt")
    Check(zip_entry_write(z, strptr(hello), len(hello)) = 0, "zip_entry_write a.txt")
    Check(zip_entry_close(z) = 0, "zip_entry_close a.txt")
    Check(zip_entry_open(z, "dir/b.bin") = 0, "zip_entry_open dir/b.bin")
    Check(zip_entry_write(z, strptr(bin256), len(bin256)) = 0, "zip_entry_write dir/b.bin")
    Check(zip_entry_close(z) = 0, "zip_entry_close dir/b.bin")
    Check(zip_entry_open(z, utf8Name) = 0, "zip_entry_open nume UTF-8")
    Check(zip_entry_write(z, strptr(hello), len(hello)) = 0, "zip_entry_write nume UTF-8")
    Check(zip_entry_close(z) = 0, "zip_entry_close nume UTF-8")
    zip_close(z)
end scope

'' ---- citire din fisier
scope
    dim as zip_t ptr z = zip_open(zipPath, 0, asc("r"))
    Check(z <> 0, "zip_open r")
    Check(zip_entries_total(z) = 3, "zip_entries_total = 3")
    Check(zip_is64(z) >= 0, "zip_is64")
    dim as ulongint ofs = 12345
    Check(zip_offset(z, @ofs) = 0 andalso ofs = 0, "zip_offset = 0")

    Check(zip_entry_open(z, "A.TXT") = 0, "zip_entry_open fara diferenta de majuscule")
    '' la citire, zip_entry_name intoarce numele cerut, nu pe cel din arhiva
    Check(*zip_entry_name(z) = "A.TXT", "zip_entry_name = numele cerut")
    zip_entry_close(z)
    Check(zip_entry_opencasesensitive(z, "A.TXT") = ZIP_ENOENT, "zip_entry_opencasesensitive A.TXT = ZIP_ENOENT")

    Check(zip_entry_open(z, "a.txt") = 0, "zip_entry_open a.txt")
    Check(zip_entry_index(z) = 0, "zip_entry_index = 0")
    Check(zip_entry_isdir(z) = 0, "zip_entry_isdir = 0")
    Check(zip_entry_issymlink(z) = 0, "zip_entry_issymlink = 0")
    Check(zip_entry_size(z) = 5 andalso zip_entry_uncomp_size(z) = 5, "zip_entry_size = 5")
    Check(zip_entry_comp_size(z) > 0, "zip_entry_comp_size > 0")
    Check(zip_entry_crc32(z) = &h3610A686, "zip_entry_crc32(""hello"")")
    '' prima intrare: antetul local si intrarea din directorul central sunt la offset 0
    Check(zip_entry_header_offset(z) = 0, "zip_entry_header_offset = 0")
    Check(zip_entry_dir_offset(z) = 0, "zip_entry_dir_offset = 0")

    dim as any ptr buf = 0
    dim as uinteger bufsize = 0
    Check(zip_entry_read(z, @buf, @bufsize) = 5 andalso bufsize = 5, "zip_entry_read = 5")
    if buf <> 0 then
        Check(memcmp(buf, strptr(hello), 5) = 0, "zip_entry_read: continut")
        deallocate(buf)
    end if

    dim as string tmp = space(5)
    Check(zip_entry_noallocread(z, strptr(tmp), 5) = 5 andalso tmp = hello, "zip_entry_noallocread")
    tmp = space(3)
    Check(zip_entry_noallocreadwithoffset(z, 1, 3, strptr(tmp)) = 3 andalso tmp = "ell", _
        "zip_entry_noallocreadwithoffset(1, 3)")
    tmp = space(2)
    Check(zip_entry_noallocread(z, strptr(tmp), 2) < 0, "zip_entry_noallocread: buffer prea mic")

    dim as string collected
    Check(zip_entry_extract(z, @CollectCallback, @collected) = 0 andalso collected = hello, "zip_entry_extract")
    Check(zip_entry_fread(z, W & "\a_fread.txt") = 0, "zip_entry_fread")
    Check(ReadFileBytes(W & "\a_fread.txt") = hello, "zip_entry_fread: continut")
    Check(zip_entry_close(z) = 0, "zip_entry_close")

    Check(zip_entry_openbyindex(z, 1) = 0, "zip_entry_openbyindex(1)")
    Check(*zip_entry_name(z) = "dir/b.bin", "zip_entry_name(1)")
    Check(zip_entry_header_offset(z) > 0 andalso zip_entry_dir_offset(z) > 0, "offseturile intrarii 1 > 0")
    tmp = space(256)
    Check(zip_entry_noallocread(z, strptr(tmp), 256) = 256 andalso tmp = bin256, "dir/b.bin: 256 de octeti")
    zip_entry_close(z)

    Check(zip_entry_openbyindex(z, 2) = 0 andalso *zip_entry_name(z) = utf8Name, "nume UTF-8 dupa index")
    zip_entry_close(z)
    Check(zip_entry_open(z, utf8Name) = 0, "zip_entry_open nume UTF-8 (citire)")
    zip_entry_close(z)

    Check(zip_entry_openbyindex(z, 99) = ZIP_EINVIDX, "zip_entry_openbyindex(99) = ZIP_EINVIDX")
    Check(zip_entry_open(z, "lipsa.txt") = ZIP_ENOENT, "zip_entry_open lipsa.txt = ZIP_ENOENT")
    zip_close(z)
end scope

'' ---- erori la deschidere
scope
    dim as long e = 0
    dim as zip_t ptr z = zip_openwitherror(W & "\lipsa.zip", 0, asc("r"), @e)
    Check(z = 0 andalso e < 0, "zip_openwitherror pe arhiva lipsa (cod " & e & ")")
    e = 0
    z = zip_openwitherror(zipPath, 0, asc("x"), @e)
    Check(z = 0 andalso e = ZIP_EINVMODE, "zip_openwitherror mod invalid = ZIP_EINVMODE")
    e = 0
    z = zip_openwitherror("", 0, asc("r"), @e)
    Check(z = 0 andalso e = ZIP_EINVZIPNAME, "zip_openwitherror nume gol = ZIP_EINVZIPNAME")
end scope

'' ---- adaugare ('a') si stergere ('d')
scope
    dim as zip_t ptr z = zip_open(zipPath, ZIP_DEFAULT_COMPRESSION_LEVEL, asc("a"))
    Check(z <> 0, "zip_open a")
    WriteFileBytes(W & "\src.txt", "din fisier")
    Check(zip_entry_open(z, "src.txt") = 0, "zip_entry_open src.txt (a)")
    Check(zip_entry_fwrite(z, W & "\src.txt") = 0, "zip_entry_fwrite")
    zip_entry_close(z)
    zip_close(z)

    z = zip_open(zipPath, 0, asc("d"))
    Check(z <> 0, "zip_open d")
    dim as zstring ptr names(0 to 0) = { @"a.txt" }
    Check(zip_entries_delete(z, @names(0), 1) = 1, "zip_entries_delete a.txt")
    zip_close(z)

    z = zip_open(zipPath, 0, asc("d"))
    dim as uinteger idx(0 to 0) = { 0 }   '' dir/b.bin este acum primul
    Check(zip_entries_deletebyindex(z, @idx(0), 1) = 1, "zip_entries_deletebyindex(0)")
    zip_close(z)

    z = zip_open(zipPath, 0, asc("r"))
    Check(zip_entries_total(z) = 2, "dupa stergere raman 2 intrari")
    Check(zip_entry_open(z, "src.txt") = 0, "src.txt exista")
    dim as string tmp = space(10)
    Check(zip_entry_noallocread(z, strptr(tmp), 10) = 10 andalso tmp = "din fisier", "src.txt: continut")
    zip_entry_close(z)
    zip_close(z)
end scope

'' ---- arhiva in memorie
dim as any ptr memZip = 0
dim as uinteger memSize = 0
scope
    dim as zip_t ptr z = zip_stream_open(0, 0, ZIP_DEFAULT_COMPRESSION_LEVEL, asc("w"))
    Check(z <> 0, "zip_stream_open w")
    zip_entry_open(z, "m/x.txt")
    zip_entry_write(z, strptr(hello), len(hello))
    zip_entry_close(z)
    zip_entry_open(z, "y.txt")
    zip_entry_write(z, strptr(hello), len(hello))
    zip_entry_close(z)
    dim as integer n = zip_stream_copy(z, @memZip, @memSize)
    Check(n > 0 andalso n = memSize andalso memZip <> 0, "zip_stream_copy")
    zip_stream_close(z)

    z = zip_stream_open(memZip, memSize, 0, asc("r"))
    Check(z <> 0, "zip_stream_open r")
    Check(zip_entries_total(z) = 2, "memorie: 2 intrari")
    dim as string tmp = space(5)
    Check(zip_entry_open(z, "m/x.txt") = 0 andalso zip_entry_noallocread(z, strptr(tmp), 5) = 5 _
        andalso tmp = hello, "memorie: citire m/x.txt")
    zip_entry_close(z)
    zip_stream_close(z)

    dim as long e = 0
    z = zip_stream_openwitherror(memZip, memSize, 0, asc("w"), @e)
    Check(z = 0 andalso e = ZIP_EINVMODE, "zip_stream_openwitherror w cu buffer = ZIP_EINVMODE")

    '' 'd': biblioteca nu modifica bufferul apelantului; rezultatul vine din zip_stream_copy
    z = zip_stream_open(memZip, memSize, 0, asc("d"))
    Check(z <> 0, "zip_stream_open d")
    dim as zstring ptr names(0 to 0) = { @"y.txt" }
    Check(zip_entries_delete(z, @names(0), 1) = 1, "memorie: zip_entries_delete")
    dim as any ptr after_ = 0
    dim as uinteger afterSize = 0
    Check(zip_stream_copy(z, @after_, @afterSize) > 0, "memorie: zip_stream_copy dupa stergere")
    zip_stream_close(z)
    z = zip_stream_open(after_, afterSize, 0, asc("r"))
    Check(z <> 0 andalso zip_entries_total(z) = 1, "memorie: 1 intrare dupa stergere")
    zip_stream_close(z)
    deallocate(after_)

    dim as long counter(0 to 1)
    mkdir W & "\din_memorie"
    Check(zip_stream_extract(memZip, memSize, W & "\din_memorie", @CountCallback, @counter(0)) = 0 _
        andalso counter(0) = 2, "zip_stream_extract")
    Check(ReadFileBytes(W & "\din_memorie\m\x.txt") = hello, "zip_stream_extract: continut")
end scope

'' ---- FILE* (zip_cstream_*)
scope
    WriteFileBytes(W & "\mem.zip", "")
    dim as long f = freefile
    open W & "\mem.zip" for binary access write as #f
    dim as string bytes = space(memSize)
    memcpy(strptr(bytes), memZip, memSize)
    put #f, , bytes
    close #f

    dim as FILE ptr fp = fopen(W & "\mem.zip", "rb")
    Check(fp <> 0, "fopen mem.zip")
    if fp <> 0 then
        dim as long e = 0
        dim as zip_t ptr z = zip_cstream_openwitherror(fp, 0, asc("r"), @e)
        Check(z <> 0 andalso e = 0, "zip_cstream_openwitherror r")
        Check(zip_entries_total(z) = 2, "cstream: 2 intrari")
        zip_cstream_close(z)
        fclose(fp)
    end if
end scope
deallocate(memZip)

'' ---- parola (PKWARE)
scope
    dim as string pwPath = W & "\parola.zip"
    dim as zip_t ptr z = zip_open_with_password(pwPath, ZIP_DEFAULT_COMPRESSION_LEVEL, asc("w"), "secret")
    Check(z <> 0, "zip_open_with_password w")
    zip_entry_open(z, "s.txt")
    zip_entry_write(z, strptr(hello), len(hello))
    zip_entry_close(z)
    zip_close(z)

    dim as long e = 0
    dim as string tmp = space(5)
    z = zip_open_with_password_and_error(pwPath, 0, asc("r"), "secret", @e)
    Check(z <> 0 andalso e = 0, "zip_open_with_password_and_error r")
    Check(zip_entry_open(z, "s.txt") = 0 andalso zip_entry_noallocread(z, strptr(tmp), 5) = 5 _
        andalso tmp = hello, "parola corecta: continut")
    zip_entry_close(z)
    zip_close(z)

    z = zip_open_with_password(pwPath, 0, asc("r"), "gresita")
    dim as long r = zip_entry_open(z, "s.txt")
    if r = 0 then r = zip_entry_noallocread(z, strptr(tmp), 5)
    Check(r = ZIP_EPASSWD, "parola gresita = ZIP_EPASSWD (" & r & ")")
    zip_entry_close(z)
    zip_close(z)

    z = zip_open(pwPath, 0, asc("r"))
    r = zip_entry_open(z, "s.txt")
    if r = 0 then r = zip_entry_noallocread(z, strptr(tmp), 5)
    '' fara parola biblioteca nu ajunge la ZIP_EPASSWD: miniz refuza intrarea criptata (ZIP_EMEMNOALLOC)
    Check(r < 0, "fara parola: eroare (" & r & ")")
    zip_entry_close(z)
    zip_close(z)
end scope

'' ---- zip_create si zip_extract
scope
    WriteFileBytes(W & "\f1.txt", "unu")
    WriteFileBytes(W & "\f2.txt", "doi")
    dim as string p1 = W & "\f1.txt", p2 = W & "\f2.txt"
    dim as const zstring ptr files(0 to 1) = { strptr(p1), strptr(p2) }
    Check(zip_create(W & "\c.zip", @files(0), 2) = 0, "zip_create")

    dim as long counter(0 to 1)
    mkdir W & "\extras"
    Check(zip_extract(W & "\c.zip", W & "\extras", @CountCallback, @counter(0)) = 0 andalso counter(0) = 2, _
        "zip_extract cu apel invers")
    Check(ReadFileBytes(W & "\extras\f1.txt") = "unu" andalso ReadFileBytes(W & "\extras\f2.txt") = "doi", _
        "zip_extract: continut")

    counter(0) = 0 : counter(1) = 1
    mkdir W & "\oprit"
    '' apelul invers negativ opreste extragerea, dar zip_extract intoarce totusi 0
    Check(zip_extract(W & "\c.zip", W & "\oprit", @CountCallback, @counter(0)) = 0 andalso counter(0) = 1, _
        "zip_extract oprit de apelul invers dupa primul fisier")
    Check(zip_extract(W & "\c.zip", W & "\nu_exista", 0, 0) = ZIP_ENOFILE, _
        "zip_extract in director inexistent = ZIP_ENOFILE")
end scope

print "test_c: " & (checks - failures) & "/" & checks & " verificari trecute"
if failures > 0 then end 1
