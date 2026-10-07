'' zipfb.bi - nivelul 2: clasa ZipArchive peste zip_c.bi (FBC-Modern).
''
'' Numele de intrari si caile sunt USTRING (convertite la UTF-8 pentru biblioteca); datele
'' intrarilor sunt STRING (octeti, nu text). Metodele intorc 0 sau un numar pozitiv la succes
'' si un cod de eroare ZIP_E* (< 0) la esec; ultimul cod ramane in LastError.
''
'' Implementarea e in lib\libzip_fb.a (build_lib.cmd). Un program se compileaza cu
''   fbc64 -i freebasic\inc -p freebasic\lib -p freebasic\bin-win64 program.bas

#pragma once

'' inainte de zip_c.bi: ld cauta simbolurile lui libzip_fb.a in bibliotecile de dupa ea
#inclib "zip_fb"
#include once "zip_c.bi"

'' modul in care se deschide o arhiva
enum ZipMode
    ZipRead = 114      '' "r": citire
    ZipWrite = 119     '' "w": arhiva noua (un fisier existent se suprascrie)
    ZipAppend = 97     '' "a": adaugare la o arhiva existenta
    ZipDelete = 100    '' "d": stergere de intrari dintr-o arhiva existenta
end enum

'' o intrare din arhiva
type ZipEntryInfo
    as ustring Name            '' numele din arhiva, cu "/" ca separator
    as integer Index = -1
    as boolean IsDirectory
    as boolean IsSymlink
    as ulongint Size           '' dimensiunea necomprimata
    as ulongint CompressedSize
    as ulong Crc32
end type

'' apelat dupa fiecare fisier extras de ExtractAll / ExtractAllFromMemory, cu calea lui;
'' o valoare negativa opreste extragerea, iar metoda intoarce acea valoare
type ZipExtractCallback as function(byref path as const ustring, byval userData as any ptr) as long

type ZipArchive
public:
    declare constructor()
    declare destructor()

    '' ---- deschidere si inchidere
    '' fisier: openMode ZipRead, ZipWrite, ZipAppend sau ZipDelete; level 0-9 (doar la scriere);
    '' password: criptare PKWARE la scriere, decriptare la citire ("" = fara parola)
    declare function OpenFile(byref path as const ustring, byval openMode as ZipMode = ZipRead, _
        byval level as long = ZIP_DEFAULT_COMPRESSION_LEVEL, byref password as const ustring = "") as long
    '' arhiva din memorie: openMode ZipRead sau ZipDelete; datele se copiaza in obiect
    declare function OpenMemory(byref bytes as const string, byval openMode as ZipMode = ZipRead, _
        byref password as const ustring = "") as long
    '' arhiva noua in memorie; rezultatul se ia cu ToBytes
    declare function CreateInMemory(byval level as long = ZIP_DEFAULT_COMPRESSION_LEVEL, _
        byref password as const ustring = "") as long
    '' octetii unei arhive din memorie (dupa CreateInMemory sau OpenMemory cu ZipDelete);
    '' dupa ToBytes o arhiva creata in memorie nu mai primeste intrari
    declare function ToBytes(byref bytes as string) as long
    '' inchide arhiva (o arhiva scrisa intr-un fisier se finalizeaza aici); se apeleaza si din destructor
    declare sub Close()

    declare property IsOpen() as boolean
    declare property Mode() as ZipMode
    declare property LastError() as long
    declare function LastErrorText() as ustring

    '' ---- continut
    declare property Count() as integer
    declare function IsZip64() as boolean
    declare function GetEntry(byval index as integer, byref info as ZipEntryInfo) as long
    '' cautarea nu tine cont de majuscule, ca in biblioteca
    declare function FindEntry(byref name_ as const ustring, byref info as ZipEntryInfo) as long
    declare function Contains(byref name_ as const ustring) as boolean
    '' umple entries() (redimensionat 0..n-1) si intoarce n
    declare function ListEntries(entries() as ZipEntryInfo) as integer

    '' ---- scriere (ZipWrite, ZipAppend, CreateInMemory)
    declare function AddBytes(byref name_ as const ustring, byref bytes as const string) as long
    '' textul se scrie ca UTF-8
    declare function AddText(byref name_ as const ustring, byref text as const ustring) as long
    declare function AddFile(byref name_ as const ustring, byref path as const ustring) as long
    '' intrare de director ("nume/")
    declare function AddDirectory(byref name_ as const ustring) as long

    '' ---- citire (ZipRead)
    declare function ReadBytes(byref name_ as const ustring, byref bytes as string) as long
    declare function ReadBytesAt(byval index as integer, byref bytes as string) as long
    '' continutul se citeste ca UTF-8
    declare function ReadText(byref name_ as const ustring, byref text as ustring) as long
    '' scrie intrarea in fisierul path (directorul lui trebuie sa existe)
    declare function ExtractEntry(byref name_ as const ustring, byref path as const ustring) as long

    '' ---- stergere (ZipDelete); intorc numarul de intrari sterse
    declare function DeleteEntries(names() as ustring) as integer
    declare function DeleteEntriesAt(indexes() as integer) as integer

    '' ---- operatii pe arhive intregi
    '' extrage tot in directorul dir, care trebuie sa existe; subdirectoarele se creeaza
    declare static function ExtractAll(byref zipPath as const ustring, byref dir_ as const ustring, _
        byval callback as ZipExtractCallback = 0, byval userData as any ptr = 0) as long
    declare static function ExtractAllFromMemory(byref bytes as const string, byref dir_ as const ustring, _
        byval callback as ZipExtractCallback = 0, byval userData as any ptr = 0) as long
    '' arhiva noua cu fisierele date, fiecare sub numele lui (fara director)
    declare static function CreateFromFiles(byref zipPath as const ustring, files() as ustring) as long
    declare static function ErrorText(byval code as long) as ustring

private:
    as zip_t ptr handle_
    as ZipMode mode_ = ZipRead
    as boolean inMemory_
    as string memory_          '' copia datelor pentru OpenMemory: biblioteca nu le copiaza
    as long lastError_

    declare function SetResult(byval code as long) as long
    declare function NotOpen() as boolean
    declare function ReadOpenEntry(byref bytes as string) as long
    declare function FillInfo(byref info as ZipEntryInfo) as long

    '' o arhiva nu se copiaza (ar fi inchisa de doua ori)
    declare constructor(byref as const ZipArchive)
    declare operator let(byref as const ZipArchive)
end type
