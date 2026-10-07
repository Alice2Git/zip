'' test_fb.bas - nivelul 2 (zipfb.bi): clasa ZipArchive.
''
''   test_fb.exe <director_iesire>
''
'' Fiecare rulare lucreaza intr-un subdirector nou (fb_<data>_<ora>[_n]) al directorului de iesire.
'' Caile si numele de intrari contin diacritice; daca directorul e pe un disc local, se testeaza
'' si calea UNC \\localhost\<disc>$\... (sarit daca share-ul administrativ nu e accesibil) si
'' prefixul \\?\.

#include once "zipfb.bi"
#include once "windows.bi"

dim shared as long checks, failures

sub Check(byval ok as boolean, byref what as const string)
    checks += 1
    if ok = false then
        failures += 1
        print "  ESEC: " & what
    end if
end sub

'' ---- fisiere cu nume Unicode (Win32 W)

function MakeDir(byref p as const ustring) as boolean
    if CreateDirectoryW(p, 0) <> 0 then return true
    return GetLastError() = ERROR_ALREADY_EXISTS
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

sub WriteAll(byref p as const ustring, byref s as const string)
    dim as HANDLE h = CreateFileW(p, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0)
    if h = INVALID_HANDLE_VALUE then exit sub
    dim as DWORD written = 0
    if len(s) > 0 then WriteFile(h, strptr(s), len(s), @written, 0)
    CloseHandle(h)
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

'' cale absoluta a unui director existent
function FullPath(byref p as const string) as string
    dim as string buf = space(1024)
    dim as DWORD n = GetFullPathNameA(p, 1024, strptr(buf), 0)
    return left(buf, n)
end function

'' ---- apelul invers pentru ExtractAll

type ExtractLog
    as long count
    as long stopAfter      '' > 0: opreste dupa atatea fisiere, cu codul -7
    as ustring lastPath
end type

function OnExtract(byref path as const ustring, byval userData as any ptr) as long
    dim as ExtractLog ptr lg = userData
    lg->count += 1
    lg->lastPath = path
    if lg->stopAfter > 0 andalso lg->count >= lg->stopAfter then return -7
    return 0
end function

'' ---- date de test

dim as ustring a_ = wchr(&h103), i_ = wchr(&hEE), ac = wchr(&hE2), s_ = wchr(&h219), t_ = wchr(&h21B)
dim as ustring capS = wchr(&h218), euro = wchr(&h20AC)
dim as ustring romana = "rom" & ac & "n" & a_                       '' "romana" cu diacritice
dim as ustring textRo = capS & "ir cu diacritice " & a_ & i_ & ac & s_ & t_ & " " & euro
dim as string textRo8 = textRo                                      '' aceleasi caractere, ca octeti UTF-8
dim as string bin256 = space(256)
for i as long = 0 to 255
    bin256[i] = i
next

dim as string outRoot = command(1)
if len(outRoot) = 0 then outRoot = exepath & "\out"
dim as string runDir = NewRunDir(outRoot, "fb_")
if len(runDir) = 0 then
    print "nu pot crea directorul de lucru in " & outRoot
    end 2
end if
runDir = FullPath(runDir)
print "test_fb: " & runDir

'' directorul de lucru are diacritice in nume
dim as ustring W = runDir & "\arhiv" & a_ & "-" & a_ & i_ & s_ & t_
Check(MakeDir(W), "MakeDir director cu diacritice")
dim as ustring zipPath = W & "\test.zip"
dim as ustring srcFile = W & "\surs" & a_ & ".txt"
WriteAll(srcFile, "din fisier")

'' ---- obiect neinchis / erori
scope
    dim as ZipArchive z
    Check(z.IsOpen = false, "obiect nou: IsOpen = false")
    Check(z.Count = 0 andalso z.LastError = ZIP_ENOINIT, "Count pe arhiva nedeschisa: ZIP_ENOINIT")
    Check(z.AddText("a.txt", "x") = ZIP_ENOINIT, "AddText pe arhiva nedeschisa")
    Check(z.OpenFile(W & "\lipsa.zip") < 0 andalso z.IsOpen = false, "OpenFile pe arhiva lipsa")
    Check(z.LastError < 0 andalso len(z.LastErrorText()) > 0, "LastErrorText dupa esec")
    Check(z.OpenFile("") = ZIP_EINVZIPNAME, "OpenFile cu nume gol = ZIP_EINVZIPNAME")
    Check(ZipArchive.ErrorText(ZIP_ENOENT) = "entry not found", "ErrorText(ZIP_ENOENT)")
    Check(left(ZipArchive.ErrorText(-1000), 13) = "unknown error", "ErrorText(cod necunoscut)")
end scope

'' ---- scriere
scope
    dim as ZipArchive z
    Check(z.OpenFile(zipPath, ZipWrite) = 0 andalso z.IsOpen andalso z.Mode = ZipWrite, "OpenFile ZipWrite")
    Check(z.AddText("text/" & romana & ".txt", textRo) = 0, "AddText cu nume si text cu diacritice")
    Check(z.AddText("hello.txt", "hello") = 0, "AddText hello.txt")
    Check(z.AddBytes("bin/all.bin", bin256) = 0, "AddBytes 256 de octeti")
    Check(z.AddBytes("gol.txt", "") = 0, "AddBytes intrare goala")
    Check(z.AddDirectory("dir_gol") = 0, "AddDirectory")
    Check(z.AddFile("din_fisier.txt", srcFile) = 0, "AddFile din cale cu diacritice")
    Check(z.AddFile("x.txt", W & "\lipsa.txt") = ZIP_ENOFILE, "AddFile din fisier lipsa = ZIP_ENOFILE")
    Check(z.AddFile("x.txt", W) = ZIP_ENOFILE, "AddFile dintr-un director = ZIP_ENOFILE")
    dim as ustring t
    Check(z.ReadText("hello.txt", t) = ZIP_EINVMODE, "ReadText in ZipWrite = ZIP_EINVMODE")
    Check(z.Contains("hello.txt") = false andalso z.LastError = ZIP_EINVMODE, "Contains in ZipWrite")
    z.Close()
    Check(z.IsOpen = false, "Close")
end scope

'' ---- citire
scope
    dim as ZipArchive z
    Check(z.OpenFile(zipPath) = 0 andalso z.Mode = ZipRead, "OpenFile ZipRead")
    '' AddFile esuat nu a lasat nicio intrare
    dim as integer n = z.Count
    Check(n = 6, "Count = 6 (" & n & ")")
    '' biblioteca scrie arhivele noi ("w") in format zip64
    Check(z.IsZip64() andalso z.LastError = 0, "IsZip64 = true")

    dim as ZipEntryInfo list()
    Check(z.ListEntries(list()) = 6 andalso ubound(list) = 5, "ListEntries = 6")
    if ubound(list) = 5 then
        Check(list(0).Name = "text/" & romana & ".txt" andalso list(0).Index = 0, "ListEntries(0): nume UTF-8")
        Check(list(0).Size = len(textRo8), "ListEntries(0): Size = octetii UTF-8")
        Check(list(1).Name = "hello.txt" andalso list(1).Crc32 = &h3610A686, "ListEntries(1): Crc32")
        Check(list(2).Size = 256 andalso list(2).CompressedSize > 0, "ListEntries(2): dimensiuni")
        Check(list(3).Name = "gol.txt" andalso list(3).Size = 0, "ListEntries(3): intrare goala")
        Check(list(4).Name = "dir_gol/" andalso list(4).IsDirectory, "ListEntries(4): director")
        Check(list(5).IsDirectory = false andalso list(5).IsSymlink = false, "ListEntries(5): fisier")
    end if

    dim as ZipEntryInfo info
    Check(z.FindEntry("HELLO.TXT", info) = 0 andalso info.Name = "hello.txt" andalso info.Index = 1, _
        "FindEntry fara diferenta de majuscule da numele din arhiva")
    Check(z.Contains("lipsa.txt") = false andalso z.LastError = ZIP_ENOENT, "Contains(lipsa) = false, ZIP_ENOENT")
    Check(z.GetEntry(99, info) = ZIP_EINVIDX, "GetEntry(99) = ZIP_EINVIDX")
    Check(z.GetEntry(-1, info) = ZIP_EINVIDX, "GetEntry(-1) = ZIP_EINVIDX")

    dim as ustring t
    Check(z.ReadText("text/" & romana & ".txt", t) = 0 andalso t = textRo, "ReadText cu diacritice")
    dim as string b
    Check(z.ReadBytes("bin/all.bin", b) = 0 andalso b = bin256, "ReadBytes binar")
    Check(z.ReadBytesAt(1, b) = 0 andalso b = "hello", "ReadBytesAt(1)")
    Check(z.ReadBytes("gol.txt", b) = 0 andalso len(b) = 0, "ReadBytes intrare goala")
    Check(z.ReadBytes("din_fisier.txt", b) = 0 andalso b = "din fisier", "ReadBytes intrare din AddFile")
    Check(z.ReadBytes("dir_gol/", b) = ZIP_EINVENTTYPE, "ReadBytes pe director = ZIP_EINVENTTYPE")
    Check(z.ReadBytes("lipsa.txt", b) = ZIP_ENOENT andalso z.LastError = ZIP_ENOENT, "ReadBytes lipsa = ZIP_ENOENT")
    Check(z.LastErrorText() = "entry not found", "LastErrorText")
    Check(z.ReadBytes("hello.txt", b) = 0 andalso z.LastError = 0, "LastError revine la 0 dupa succes")

    dim as ustring outFile = W & "\" & romana & "-extras.txt"
    Check(z.ExtractEntry("text/" & romana & ".txt", outFile) = 0, "ExtractEntry in cale cu diacritice")
    Check(ReadAll(outFile) = textRo8, "ExtractEntry: continut UTF-8")
    Check(z.AddText("a.txt", "x") = ZIP_EINVMODE, "AddText in ZipRead = ZIP_EINVMODE")

    '' OpenFile pe un obiect deschis inchide arhiva anterioara
    Check(z.OpenFile(zipPath) = 0 andalso z.Count = 6, "OpenFile din nou pe acelasi obiect")
end scope

'' ---- adaugare
scope
    dim as ZipArchive z
    Check(z.OpenFile(zipPath, ZipAppend) = 0 andalso z.Mode = ZipAppend, "OpenFile ZipAppend")
    Check(z.AddText("adaugat.txt", "nou") = 0, "AddText in ZipAppend")
    z.Close()
    dim as ustring t
    Check(z.OpenFile(zipPath) = 0 andalso z.Count = 7 andalso z.ReadText("adaugat.txt", t) = 0 _
        andalso t = "nou", "dupa ZipAppend: 7 intrari")
end scope

'' ---- stergere din fisier
scope
    dim as ZipArchive z
    Check(z.OpenFile(zipPath, ZipDelete) = 0 andalso z.Mode = ZipDelete, "OpenFile ZipDelete")
    dim as ustring names(0 to 1) = { "gol.txt", "bin/all.bin" }
    Check(z.DeleteEntries(names()) = 2, "DeleteEntries 2")
    dim as ustring t
    Check(z.ReadText("hello.txt", t) = ZIP_EINVMODE, "ReadText in ZipDelete = ZIP_EINVMODE")
    z.Close()

    Check(z.OpenFile(zipPath, ZipDelete) = 0, "OpenFile ZipDelete (2)")
    dim as integer idx(0 to 0) = { 0 }
    Check(z.DeleteEntriesAt(idx()) = 1, "DeleteEntriesAt(0)")
    dim as integer bad(0 to 0) = { -1 }
    Check(z.DeleteEntriesAt(bad()) = ZIP_EINVIDX, "DeleteEntriesAt(-1) = ZIP_EINVIDX")
    dim as ustring none()
    Check(z.DeleteEntries(none()) = 0, "DeleteEntries cu lista goala")
    z.Close()

    dim as long r = z.OpenFile(zipPath)
    dim as integer n = z.Count
    Check(r = 0 andalso n = 4, "dupa stergere: 4 intrari (" & n & ")")
    Check(z.Contains("text/" & romana & ".txt") = false andalso z.Contains("hello.txt"), _
        "dupa stergere: au ramas intrarile corecte")
end scope

'' ---- arhiva in memorie
dim as string memZip
scope
    dim as ZipArchive z
    Check(z.CreateInMemory() = 0 andalso z.Mode = ZipWrite, "CreateInMemory")
    Check(z.AddText("m/" & romana & ".txt", textRo) = 0, "memorie: AddText")
    Check(z.AddBytes("m/all.bin", bin256) = 0, "memorie: AddBytes")
    Check(z.AddText("sterge.txt", "x") = 0, "memorie: AddText sterge.txt")
    Check(z.ToBytes(memZip) = 0 andalso len(memZip) > 0, "ToBytes")
    Check(left(memZip, 2) = "PK", "ToBytes: semnatura PK")
    z.Close()

    dim as ZipArchive f
    Check(f.OpenFile(W & "\fisier.zip", ZipWrite) = 0, "arhiva pe disc pentru ToBytes")
    dim as string b
    Check(f.ToBytes(b) = ZIP_EINVMODE andalso len(b) = 0, "ToBytes pe arhiva din fisier = ZIP_EINVMODE")

    '' obiectul pastreaza propria copie: sirul apelantului poate disparea
    scope
        dim as string tmp = memZip
        Check(z.OpenMemory(tmp) = 0 andalso z.Mode = ZipRead, "OpenMemory")
        tmp = string(len(tmp), "Z")
    end scope
    dim as ustring t
    Check(z.Count = 3 andalso z.ReadText("m/" & romana & ".txt", t) = 0 andalso t = textRo, _
        "OpenMemory: citire dupa ce sirul sursa s-a schimbat")
    Check(z.ReadBytes("m/all.bin", b) = 0 andalso b = bin256, "OpenMemory: ReadBytes")
    Check(z.ToBytes(b) = 0 andalso b = memZip, "ToBytes pe arhiva deschisa din memorie")

    Check(z.OpenMemory(memZip, ZipDelete) = 0 andalso z.Mode = ZipDelete, "OpenMemory ZipDelete")
    dim as ustring names(0 to 0) = { "sterge.txt" }
    Check(z.DeleteEntries(names()) = 1, "memorie: DeleteEntries")
    dim as string after_
    Check(z.ToBytes(after_) = 0 andalso len(after_) > 0 andalso len(after_) < len(memZip), "memorie: ToBytes dupa stergere")
    Check(z.OpenMemory(after_) = 0 andalso z.Count = 2, "memorie: 2 intrari dupa stergere")
    Check(z.Contains("sterge.txt") = false, "memorie: sterge.txt nu mai exista")

    Check(z.OpenMemory("nu e zip") = ZIP_ERINIT andalso z.IsOpen = false, "OpenMemory pe date invalide = ZIP_ERINIT")
    Check(z.OpenMemory("") = ZIP_EINVMODE, "OpenMemory pe sir gol = ZIP_EINVMODE")
    Check(z.OpenMemory(memZip, ZipWrite) = ZIP_EINVMODE, "OpenMemory ZipWrite = ZIP_EINVMODE")
end scope

'' ---- parola
scope
    dim as ustring pw = "parol" & a_
    dim as ustring pwZip = W & "\parol" & a_ & ".zip"
    dim as ZipArchive z
    Check(z.OpenFile(pwZip, ZipWrite, ZIP_DEFAULT_COMPRESSION_LEVEL, pw) = 0, "OpenFile ZipWrite cu parola")
    Check(z.AddText("secret.txt", textRo) = 0, "AddText cu parola")
    z.Close()

    dim as ustring t
    Check(z.OpenFile(pwZip, ZipRead, 0, pw) = 0 andalso z.ReadText("secret.txt", t) = 0 andalso t = textRo, _
        "citire cu parola corecta")
    Check(z.OpenFile(pwZip, ZipRead, 0, "gresita") = 0 andalso z.ReadText("secret.txt", t) = ZIP_EPASSWD, _
        "citire cu parola gresita = ZIP_EPASSWD")
    Check(z.OpenFile(pwZip) = 0 andalso z.ReadText("secret.txt", t) < 0, "citire fara parola = eroare")

    dim as string b
    Check(z.CreateInMemory(ZIP_DEFAULT_COMPRESSION_LEVEL, pw) = 0 andalso z.AddText("s.txt", "abc") = 0 _
        andalso z.ToBytes(b) = 0, "CreateInMemory cu parola")
    Check(z.OpenMemory(b, ZipRead, pw) = 0 andalso z.ReadText("s.txt", t) = 0 andalso t = "abc", _
        "OpenMemory cu parola corecta")
    Check(z.OpenMemory(b, ZipRead, "gresita") = 0 andalso z.ReadText("s.txt", t) = ZIP_EPASSWD, _
        "OpenMemory cu parola gresita = ZIP_EPASSWD")
    Check(z.OpenMemory("nu e zip", ZipRead, pw) = ZIP_ERINIT, "OpenMemory cu parola pe date invalide = ZIP_ERINIT")
end scope

'' ---- extragere completa
scope
    dim as ustring dest = W & "\extras-" & s_ & t_
    Check(MakeDir(dest), "MakeDir destinatie")
    dim as ExtractLog lg
    dim as long r = ZipArchive.ExtractAll(zipPath, dest, @OnExtract, @lg)
    Check(r = 0 andalso lg.count = 4, "ExtractAll cu apel invers (" & r & ", " & lg.count & ")")
    Check(right(lg.lastPath, 11) = "adaugat.txt", "ExtractAll: calea data apelului invers")
    Check(ReadAll(dest & "\din_fisier.txt") = "din fisier", "ExtractAll: continut")
    Check(FileExists(dest & "\hello.txt"), "ExtractAll: hello.txt")

    dim as ustring dest2 = W & "\oprit"
    MakeDir(dest2)
    dim as ExtractLog stopLog
    stopLog.stopAfter = 2
    Check(ZipArchive.ExtractAll(zipPath, dest2, @OnExtract, @stopLog) = -7 andalso stopLog.count = 2, _
        "ExtractAll oprit de apelul invers intoarce codul lui")

    Check(ZipArchive.ExtractAll(zipPath, W & "\nu_exista") = ZIP_ENOFILE, "ExtractAll in director lipsa = ZIP_ENOFILE")
    Check(ZipArchive.ExtractAll(W & "\lipsa.zip", dest) < 0, "ExtractAll pe arhiva lipsa")

    dim as ustring dest3 = W & "\din-memorie"
    MakeDir(dest3)
    dim as ExtractLog memLog
    Check(ZipArchive.ExtractAllFromMemory(memZip, dest3, @OnExtract, @memLog) = 0 andalso memLog.count = 3, _
        "ExtractAllFromMemory")
    Check(ReadAll(dest3 & "\m\" & romana & ".txt") = textRo8, "ExtractAllFromMemory: continut")
end scope

'' ---- CreateFromFiles
scope
    dim as ustring f1 = W & "\unu-" & a_ & ".txt", f2 = W & "\doi-" & t_ & ".txt"
    WriteAll(f1, "1")
    WriteAll(f2, "2")
    dim as ustring files(0 to 1) = { f1, f2 }
    dim as ustring created = W & "\creat-" & i_ & ".zip"
    Check(ZipArchive.CreateFromFiles(created, files()) = 0, "CreateFromFiles")
    dim as ZipArchive z
    dim as ZipEntryInfo list()
    Check(z.OpenFile(created) = 0 andalso z.ListEntries(list()) = 2, "CreateFromFiles: 2 intrari")
    if ubound(list) = 1 then
        Check(list(0).Name = "unu-" & a_ & ".txt" andalso list(1).Name = "doi-" & t_ & ".txt", _
            "CreateFromFiles: numele fara director")
    end if
    dim as string b
    Check(z.ReadBytes("doi-" & t_ & ".txt", b) = 0 andalso b = "2", "CreateFromFiles: continut")
end scope

'' ---- UNC si \\?\
sub PathRoundTrip(byref label as const string, byref base_ as const ustring)
    dim as ZipArchive z
    dim as ustring p = base_ & "\cale.zip"
    Check(z.OpenFile(p, ZipWrite) = 0 andalso z.AddText("a/b.txt", "unc") = 0, label & ": scriere")
    z.Close()
    dim as ustring t
    Check(z.OpenFile(p) = 0 andalso z.ReadText("a/b.txt", t) = 0 andalso t = "unc", label & ": citire")
    z.Close()
    dim as ustring dest = base_ & "\dest"
    MakeDir(dest)
    Check(ZipArchive.ExtractAll(p, dest) = 0, label & ": ExtractAll")
    '' un fisier din aceeasi cale (cu \\?\, ".." nu s-ar normaliza)
    dim as ustring src = base_ & "\surs" & wchr(&h103) & ".txt"
    WriteAll(src, "sursa")
    Check(z.OpenFile(p, ZipAppend) = 0 andalso z.AddFile("src.txt", src) = 0, label & ": AddFile")
end sub

scope
    dim as ustring local_ = W & "\cai"
    MakeDir(local_)
    if mid(runDir, 2, 1) = ":" then
        dim as ustring unc = "\\localhost\" & left(runDir, 1) & "$" & mid(W & "\cai", 3)
        if GetFileAttributesW(unc) <> INVALID_FILE_ATTRIBUTES then
            PathRoundTrip("UNC", unc)
            Check(FileExists(local_ & "\dest\a\b.txt"), "UNC: fisierul extras")
        else
            print "  (UNC sarit: " & unc & " nu e accesibil)"
        end if
        dim as ustring lp = "\\?\" & W & "\cai"
        dim as ustring sub_ = lp & "\lung"
        MakeDir(sub_)
        PathRoundTrip("\\?\", sub_)
        Check(FileExists(local_ & "\lung\dest\a\b.txt"), "\\?\: fisierul extras")
    end if
end scope

print "test_fb: " & (checks - failures) & "/" & checks & " verificari trecute"
if failures > 0 then end 1
