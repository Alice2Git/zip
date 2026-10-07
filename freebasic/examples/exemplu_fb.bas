'' exemplu_fb.bas - nivelul 2: clasa ZipArchive (FBC-Modern).
''
''   exemplu_fb.exe [director]      (implicit directorul executabilului)
''
'' Compilare: fbc64 -i freebasic\inc -p freebasic\lib -p freebasic\bin-win64 exemplu_fb.bas

#include once "zipfb.bi"

'' afiseaza fiecare fisier extras
function OnExtract(byref path as const ustring, byval userData as any ptr) as long
    print "  extras: " & path
    return 0
end function

dim as string dir_ = command(1)
if len(dir_) = 0 then dir_ = exepath
dim as ustring zipPath = dir_ & "\exemplu_fb.zip"
dim as ustring greeting = "Bun" & wchr(&h103) & " ziua, " & wchr(&h218) & "tefan!"   '' cu diacritice

'' ---- scriere
scope
    dim as ZipArchive zip
    if zip.OpenFile(zipPath, ZipWrite) < 0 then
        print "nu pot crea arhiva: " & zip.LastErrorText()
        end 1
    end if
    zip.AddText("salut.txt", greeting)
    zip.AddDirectory("gol")
    zip.AddText("documente/nota.txt", "o nota")
    dim as string bytes = chr(0, 1, 2, 255)
    zip.AddBytes("documente/date.bin", bytes)
    '' arhiva se finalizeaza la Close sau in destructor
end scope

'' ---- listare si citire
scope
    dim as ZipArchive zip
    if zip.OpenFile(zipPath) < 0 then
        print "nu pot deschide arhiva: " & zip.LastErrorText()
        end 1
    end if
    dim as ZipEntryInfo entries()
    print zipPath & ": " & zip.ListEntries(entries()) & " intrari"
    for i as integer = 0 to ubound(entries)
        with entries(i)
            print "  " & .Name & iif(.IsDirectory, "  (director)", "  " & .Size & " octeti, crc " & hex(.Crc32, 8))
        end with
    next

    dim as ustring text
    if zip.ReadText("salut.txt", text) = 0 then print "salut.txt: " & text
    if zip.ReadText("lipsa.txt", text) < 0 then print "lipsa.txt: " & zip.LastErrorText()
end scope

'' ---- extragere (directorul destinatie trebuie sa existe)
dim as string dest = dir_ & "\exemplu_fb_extras"
mkdir dest
print "extragere in " & dest
dim as long r = ZipArchive.ExtractAll(zipPath, dest, @OnExtract)
if r < 0 then print "extragere esuata: " & ZipArchive.ErrorText(r)

'' ---- arhiva in memorie
scope
    dim as ZipArchive mem
    mem.CreateInMemory()
    mem.AddText("din_memorie.txt", greeting)
    dim as string bytes
    mem.ToBytes(bytes)
    print "arhiva in memorie: " & len(bytes) & " octeti"

    dim as ZipArchive back
    dim as ustring text
    if back.OpenMemory(bytes) = 0 andalso back.ReadText("din_memorie.txt", text) = 0 then
        print "citit din memorie: " & text
    end if
end scope
