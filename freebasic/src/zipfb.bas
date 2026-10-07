'' zipfb.bas - implementarea clasei ZipArchive (nivelul 2), peste zip_c.bi.

#include once "zipfb.bi"
#include once "crt/stdlib.bi"
#include once "crt/string.bi"
#ifdef __FB_WIN32__
#include once "windows.bi"
#else
#include once "file.bi"
#endif

'' context pentru apelul invers al lui zip_extract / zip_stream_extract
type ExtractContext
    as ZipExtractCallback callback
    as any ptr userData
    as long stopCode
end type

'' traduce apelul invers C (cale UTF-8) in ZipExtractCallback (USTRING)
private function ExtractTrampoline cdecl(byval filename as const zstring ptr, byval arg as any ptr) as long
    dim as ExtractContext ptr ctx = arg
    dim as ustring path
    if filename <> 0 then path = *filename
    dim as long r = ctx->callback(path, ctx->userData)
    if r < 0 then ctx->stopCode = r
    return r
end function

'' fisier existent (nu director)
private function IsRegularFile(byref path as const ustring) as boolean
#ifdef __FB_WIN32__
    dim as DWORD a = GetFileAttributesW(path)
    return a <> INVALID_FILE_ATTRIBUTES andalso (a and FILE_ATTRIBUTE_DIRECTORY) = 0
#else
    dim as string p8 = path
    return fileexists(p8)
#endif
end function

'' parola pentru biblioteca: NULL inseamna fara parola
private function PasswordPtr(byref pw8 as const string) as const zstring ptr
    if len(pw8) = 0 then return 0
    return strptr(pw8)
end function

constructor ZipArchive()
end constructor

destructor ZipArchive()
    this.Close()
end destructor

function ZipArchive.SetResult(byval code as long) as long
    lastError_ = iif(code < 0, code, 0)
    return code
end function

function ZipArchive.NotOpen() as boolean
    if handle_ <> 0 then return false
    lastError_ = ZIP_ENOINIT
    return true
end function

'' ---- deschidere si inchidere

function ZipArchive.OpenFile(byref path as const ustring, byval openMode as ZipMode, byval level as long, _
        byref password as const ustring) as long
    this.Close()
    dim as string p8 = path, pw8 = password
    dim as long e = 0
    if len(pw8) > 0 then
        handle_ = zip_open_with_password_and_error(strptr(p8), level, cbyte(openMode), strptr(pw8), @e)
    else
        handle_ = zip_openwitherror(strptr(p8), level, cbyte(openMode), @e)
    end if
    if handle_ = 0 then return SetResult(iif(e < 0, e, ZIP_ENOINIT))
    mode_ = openMode
    inMemory_ = false
    return SetResult(0)
end function

function ZipArchive.OpenMemory(byref bytes as const string, byval openMode as ZipMode, _
        byref password as const ustring) as long
    this.Close()
    if openMode <> ZipRead andalso openMode <> ZipDelete then return SetResult(ZIP_EINVMODE)
    '' biblioteca lucreaza direct pe buffer, deci obiectul pastreaza o copie cat timp e deschis
    memory_ = bytes
    dim as string pw8 = password
    dim as long e = 0
    if len(pw8) > 0 then
        handle_ = zip_stream_open_with_password(strptr(memory_), len(memory_), 0, cbyte(openMode), strptr(pw8))
        if handle_ = 0 then
            '' zip_stream_open_with_password nu da codul de eroare: acelasi apel fara parola il da
            dim as zip_t ptr probe = zip_stream_openwitherror(strptr(memory_), len(memory_), 0, cbyte(openMode), @e)
            if probe <> 0 then
                zip_stream_close(probe)
                e = ZIP_ENOINIT
            end if
        end if
    else
        handle_ = zip_stream_openwitherror(strptr(memory_), len(memory_), 0, cbyte(openMode), @e)
    end if
    if handle_ = 0 then
        memory_ = ""
        return SetResult(iif(e < 0, e, ZIP_ENOINIT))
    end if
    mode_ = openMode
    inMemory_ = true
    return SetResult(0)
end function

function ZipArchive.CreateInMemory(byval level as long, byref password as const ustring) as long
    this.Close()
    dim as string pw8 = password
    dim as long e = 0
    if len(pw8) > 0 then
        handle_ = zip_stream_open_with_password(0, 0, level, cbyte(ZipWrite), strptr(pw8))
        if handle_ = 0 then
            dim as zip_t ptr probe = zip_stream_openwitherror(0, 0, level, cbyte(ZipWrite), @e)
            if probe <> 0 then
                zip_stream_close(probe)
                e = ZIP_ENOINIT
            end if
        end if
    else
        handle_ = zip_stream_openwitherror(0, 0, level, cbyte(ZipWrite), @e)
    end if
    if handle_ = 0 then return SetResult(iif(e < 0, e, ZIP_ENOINIT))
    mode_ = ZipWrite
    inMemory_ = true
    return SetResult(0)
end function

function ZipArchive.ToBytes(byref bytes as string) as long
    bytes = ""
    if NotOpen() then return ZIP_ENOINIT
    if inMemory_ = false then return SetResult(ZIP_EINVMODE)
    dim as any ptr buf = 0
    dim as uinteger n = 0
    dim as integer r = zip_stream_copy(handle_, @buf, @n)
    if r < 0 then return SetResult(r)
    bytes = space(n)
    if n > 0 then memcpy(strptr(bytes), buf, n)
    '' zip_stream_copy aloca cu calloc din msvcrt.dll
    free(buf)
    return SetResult(0)
end function

sub ZipArchive.Close()
    if handle_ <> 0 then
        if inMemory_ then
            zip_stream_close(handle_)
        else
            zip_close(handle_)
        end if
        handle_ = 0
    end if
    memory_ = ""
    inMemory_ = false
    mode_ = ZipRead
end sub

property ZipArchive.IsOpen() as boolean
    return handle_ <> 0
end property

property ZipArchive.Mode() as ZipMode
    return mode_
end property

property ZipArchive.LastError() as long
    return lastError_
end property

function ZipArchive.LastErrorText() as ustring
    if lastError_ = 0 then return ""
    return ErrorText(lastError_)
end function

'' ---- continut

property ZipArchive.Count() as integer
    if NotOpen() then return 0
    dim as integer n = zip_entries_total(handle_)
    SetResult(iif(n < 0, n, 0))
    return iif(n < 0, 0, n)
end property

function ZipArchive.IsZip64() as boolean
    if NotOpen() then return false
    dim as long r = zip_is64(handle_)
    SetResult(iif(r < 0, r, 0))
    return r = 1
end function

'' completeaza info din intrarea deschisa (dupa index: numele e cel din arhiva)
function ZipArchive.FillInfo(byref info as ZipEntryInfo) as long
    dim as const zstring ptr n = zip_entry_name(handle_)
    if n <> 0 then info.Name = *n else info.Name = ""
    info.Index = zip_entry_index(handle_)
    info.IsDirectory = (zip_entry_isdir(handle_) = 1)
    info.IsSymlink = (zip_entry_issymlink(handle_) = 1)
    info.Size = zip_entry_size(handle_)
    info.CompressedSize = zip_entry_comp_size(handle_)
    info.Crc32 = zip_entry_crc32(handle_)
    return 0
end function

function ZipArchive.GetEntry(byval index as integer, byref info as ZipEntryInfo) as long
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipRead then return SetResult(ZIP_EINVMODE)
    if index < 0 then return SetResult(ZIP_EINVIDX)
    dim as long r = zip_entry_openbyindex(handle_, index)
    if r < 0 then return SetResult(r)
    defer zip_entry_close(handle_)
    return SetResult(FillInfo(info))
end function

function ZipArchive.FindEntry(byref name_ as const ustring, byref info as ZipEntryInfo) as long
    if NotOpen() then return ZIP_ENOINIT
    '' in celelalte moduri zip_entry_open ar adauga o intrare noua
    if mode_ <> ZipRead then return SetResult(ZIP_EINVMODE)
    dim as string n8 = name_
    dim as long r = zip_entry_open(handle_, strptr(n8))
    if r < 0 then return SetResult(r)
    '' zip_entry_name ar da numele cerut; numele din arhiva vine prin index
    dim as integer index = zip_entry_index(handle_)
    zip_entry_close(handle_)
    return GetEntry(index, info)
end function

function ZipArchive.Contains(byref name_ as const ustring) as boolean
    dim as ZipEntryInfo info
    return FindEntry(name_, info) = 0
end function

function ZipArchive.ListEntries(entries() as ZipEntryInfo) as integer
    erase entries
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipRead then return SetResult(ZIP_EINVMODE)
    dim as integer n = zip_entries_total(handle_)
    if n <= 0 then return SetResult(n)
    redim entries(0 to n - 1)
    for i as integer = 0 to n - 1
        dim as long r = GetEntry(i, entries(i))
        if r < 0 then
            erase entries
            return r
        end if
    next
    return SetResult(n)
end function

'' ---- scriere

function ZipArchive.AddBytes(byref name_ as const ustring, byref bytes as const string) as long
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipWrite andalso mode_ <> ZipAppend then return SetResult(ZIP_EINVMODE)
    dim as string n8 = name_
    dim as long r = zip_entry_open(handle_, strptr(n8))
    if r < 0 then return SetResult(r)
    if len(bytes) > 0 then r = zip_entry_write(handle_, strptr(bytes), len(bytes))
    dim as long c = zip_entry_close(handle_)
    if r = 0 then r = c
    return SetResult(r)
end function

function ZipArchive.AddText(byref name_ as const ustring, byref text as const ustring) as long
    dim as string t8 = text
    return AddBytes(name_, t8)
end function

function ZipArchive.AddFile(byref name_ as const ustring, byref path as const ustring) as long
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipWrite andalso mode_ <> ZipAppend then return SetResult(ZIP_EINVMODE)
    '' zip_entry_fwrite esuat lasa in arhiva o intrare goala (biblioteca nu poate renunta la o
    '' intrare inceputa), deci fisierul se verifica inainte de zip_entry_open
    if IsRegularFile(path) = false then return SetResult(ZIP_ENOFILE)
    dim as string n8 = name_, p8 = path
    dim as long r = zip_entry_open(handle_, strptr(n8))
    if r < 0 then return SetResult(r)
    r = zip_entry_fwrite(handle_, strptr(p8))
    dim as long c = zip_entry_close(handle_)
    if r = 0 then r = c
    return SetResult(r)
end function

function ZipArchive.AddDirectory(byref name_ as const ustring) as long
    dim as ustring d = name_
    if len(d) = 0 then return SetResult(ZIP_EINVENTNAME)
    dim as string d8 = d
    if right(d8, 1) <> "/" andalso right(d8, 1) <> "\" then d8 &= "/"
    dim as ustring withSlash = d8
    return AddBytes(withSlash, "")
end function

'' ---- citire

'' citeste intrarea deschisa intr-un STRING de dimensiunea ei
function ZipArchive.ReadOpenEntry(byref bytes as string) as long
    bytes = ""
    if zip_entry_isdir(handle_) = 1 then return ZIP_EINVENTTYPE
    dim as ulongint size = zip_entry_size(handle_)
    if size = 0 then return 0
    bytes = space(size)
    dim as integer r = zip_entry_noallocread(handle_, strptr(bytes), size)
    if r < 0 then
        bytes = ""
        return r
    end if
    if r <> size then bytes = left(bytes, r)
    return 0
end function

function ZipArchive.ReadBytes(byref name_ as const ustring, byref bytes as string) as long
    bytes = ""
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipRead then return SetResult(ZIP_EINVMODE)
    dim as string n8 = name_
    dim as long r = zip_entry_open(handle_, strptr(n8))
    if r < 0 then return SetResult(r)
    defer zip_entry_close(handle_)
    return SetResult(ReadOpenEntry(bytes))
end function

function ZipArchive.ReadBytesAt(byval index as integer, byref bytes as string) as long
    bytes = ""
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipRead then return SetResult(ZIP_EINVMODE)
    if index < 0 then return SetResult(ZIP_EINVIDX)
    dim as long r = zip_entry_openbyindex(handle_, index)
    if r < 0 then return SetResult(r)
    defer zip_entry_close(handle_)
    return SetResult(ReadOpenEntry(bytes))
end function

function ZipArchive.ReadText(byref name_ as const ustring, byref text as ustring) as long
    dim as string bytes
    dim as long r = ReadBytes(name_, bytes)
    text = bytes
    return r
end function

function ZipArchive.ExtractEntry(byref name_ as const ustring, byref path as const ustring) as long
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipRead then return SetResult(ZIP_EINVMODE)
    dim as string n8 = name_, p8 = path
    dim as long r = zip_entry_open(handle_, strptr(n8))
    if r < 0 then return SetResult(r)
    defer zip_entry_close(handle_)
    if zip_entry_isdir(handle_) = 1 then return SetResult(ZIP_EINVENTTYPE)
    return SetResult(zip_entry_fread(handle_, strptr(p8)))
end function

'' ---- stergere

function ZipArchive.DeleteEntries(names() as ustring) as integer
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipDelete then return SetResult(ZIP_EINVMODE)
    dim as integer lo = lbound(names), n = ubound(names) - lbound(names) + 1
    if n <= 0 then return SetResult(0)
    redim as string s8(0 to n - 1)
    redim as zstring ptr p(0 to n - 1)
    for i as integer = 0 to n - 1
        s8(i) = names(lo + i)
        p(i) = strptr(s8(i))
    next
    return SetResult(zip_entries_delete(handle_, @p(0), n))
end function

function ZipArchive.DeleteEntriesAt(indexes() as integer) as integer
    if NotOpen() then return ZIP_ENOINIT
    if mode_ <> ZipDelete then return SetResult(ZIP_EINVMODE)
    dim as integer lo = lbound(indexes), n = ubound(indexes) - lbound(indexes) + 1
    if n <= 0 then return SetResult(0)
    redim as uinteger idx(0 to n - 1)
    for i as integer = 0 to n - 1
        if indexes(lo + i) < 0 then return SetResult(ZIP_EINVIDX)
        idx(i) = indexes(lo + i)
    next
    return SetResult(zip_entries_deletebyindex(handle_, @idx(0), n))
end function

'' ---- operatii pe arhive intregi

static function ZipArchive.ExtractAll(byref zipPath as const ustring, byref dir_ as const ustring, _
        byval callback as ZipExtractCallback, byval userData as any ptr) as long
    dim as string z8 = zipPath, d8 = dir_
    if callback = 0 then return zip_extract(strptr(z8), strptr(d8), 0, 0)
    dim as ExtractContext ctx
    ctx.callback = callback
    ctx.userData = userData
    dim as long r = zip_extract(strptr(z8), strptr(d8), @ExtractTrampoline, @ctx)
    '' biblioteca opreste extragerea, dar intoarce 0: aici se intoarce valoarea apelului invers
    if r = 0 andalso ctx.stopCode < 0 then r = ctx.stopCode
    return r
end function

static function ZipArchive.ExtractAllFromMemory(byref bytes as const string, byref dir_ as const ustring, _
        byval callback as ZipExtractCallback, byval userData as any ptr) as long
    dim as string d8 = dir_
    if callback = 0 then return zip_stream_extract(strptr(bytes), len(bytes), strptr(d8), 0, 0)
    dim as ExtractContext ctx
    ctx.callback = callback
    ctx.userData = userData
    dim as long r = zip_stream_extract(strptr(bytes), len(bytes), strptr(d8), @ExtractTrampoline, @ctx)
    if r = 0 andalso ctx.stopCode < 0 then r = ctx.stopCode
    return r
end function

static function ZipArchive.CreateFromFiles(byref zipPath as const ustring, files() as ustring) as long
    dim as string z8 = zipPath
    dim as integer lo = lbound(files), n = ubound(files) - lbound(files) + 1
    if n <= 0 then return zip_create(strptr(z8), 0, 0)
    redim as string s8(0 to n - 1)
    redim as const zstring ptr p(0 to n - 1)
    for i as integer = 0 to n - 1
        s8(i) = files(lo + i)
        p(i) = strptr(s8(i))
    next
    return zip_create(strptr(z8), @p(0), n)
end function

static function ZipArchive.ErrorText(byval code as long) as ustring
    dim as const zstring ptr p = zip_strerror(code)
    if p = 0 then return "unknown error (" & code & ")"
    dim as ustring s = *p
    return s
end function
