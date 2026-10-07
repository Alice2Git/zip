'' exemplu_c.bas - nivelul 1: creeaza o arhiva, o listeaza si citeste o intrare, direct prin zip_c.bi.
''
''   exemplu_c.exe [director]       (implicit directorul executabilului)
''
'' Compilare: fbc64 -i freebasic\inc -p freebasic\bin-win64 exemplu_c.bas

#include once "zip_c.bi"

dim as string dir_ = command(1)
if len(dir_) = 0 then dir_ = exepath
dim as string zipPath = dir_ & "\exemplu_c.zip"

'' scriere
dim as zip_t ptr z = zip_open(zipPath, ZIP_DEFAULT_COMPRESSION_LEVEL, asc("w"))
if z = 0 then
    print "nu pot crea " & zipPath
    end 1
end if
dim as string text = "Salut din FreeBASIC!"
zip_entry_open(z, "salut.txt")
zip_entry_write(z, strptr(text), len(text))
zip_entry_close(z)
zip_entry_open(z, "date/numere.txt")
dim as string numbers = "1 2 3 4 5"
zip_entry_write(z, strptr(numbers), len(numbers))
zip_entry_close(z)
zip_close(z)

'' listare si citire
dim as long e = 0
z = zip_openwitherror(zipPath, 0, asc("r"), @e)
if z = 0 then
    print "nu pot deschide " & zipPath & ": " & *zip_strerror(e)
    end 1
end if
print zipPath & ": " & zip_entries_total(z) & " intrari"
for i as integer = 0 to zip_entries_total(z) - 1
    zip_entry_openbyindex(z, i)
    print "  " & *zip_entry_name(z) & "  " & zip_entry_size(z) & " octeti, comprimat " & zip_entry_comp_size(z)
    zip_entry_close(z)
next

if zip_entry_open(z, "salut.txt") = 0 then
    '' bufferul e alocat de biblioteca si se elibereaza cu deallocate
    dim as any ptr buf = 0
    dim as uinteger size = 0
    if zip_entry_read(z, @buf, @size) >= 0 then
        print "salut.txt: " & left(*cast(zstring ptr, buf), size)
        deallocate(buf)
    end if
    zip_entry_close(z)
end if
zip_close(z)
