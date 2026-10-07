'' zip_c.bi - legatura FreeBASIC directa (nivelul 1) la biblioteca zip (src/zip.h).
''
'' Declaratiile sunt unu la unu cu zip.h: aceleasi nume, aceiasi parametri, aceleasi reguli.
'' Se leaga cu biblioteca de import GNU libzip.dll.a (din bin-win64, dat cu -p), iar
'' libzip.dll trebuie sa stea langa executabil.
''
'' Corespondenta tipurilor:
''   char mode           -> byte        (de ex. asc("r"), asc("w"), asc("a"), asc("d"))
''   size_t              -> uinteger
''   ssize_t             -> integer     (are latimea unui pointer, ca ssize_t pe Windows)
''   uint64_t, unsigned long long -> ulongint
''   unsigned int        -> ulong
''   const char *        -> const zstring ptr (siruri UTF-8 terminate cu zero)
''   const char *stream  -> const any ptr     (bufferul unei arhive in memorie)
''
'' Toate caile si numele de intrari sunt UTF-8. Pe Windows biblioteca le converteste la
'' UTF-16 si merge si cu cai UNC (\\server\share\...) si cu prefixul \\?\.
''
'' Memoria intoarsa de zip_entry_read si zip_stream_copy e alocata cu malloc din msvcrt.dll
'' si se elibereaza cu deallocate (sau free din crt).

#pragma once

#inclib "zip"

#include once "crt/stdio.bi"

extern "C"

'' nivelul de compresie implicit
const ZIP_DEFAULT_COMPRESSION_LEVEL = 6

'' coduri de eroare
const ZIP_ENOINIT = -1       '' not initialized
const ZIP_EINVENTNAME = -2   '' invalid entry name
const ZIP_ENOENT = -3        '' entry not found
const ZIP_EINVMODE = -4      '' invalid zip mode
const ZIP_EINVLVL = -5       '' invalid compression level
const ZIP_ENOSUP64 = -6      '' no zip 64 support
const ZIP_EMEMSET = -7       '' memset error
const ZIP_EWRTENT = -8       '' cannot write data to entry
const ZIP_ETDEFLINIT = -9    '' cannot initialize tdefl compressor
const ZIP_EINVIDX = -10      '' invalid index
const ZIP_ENOHDR = -11       '' header not found
const ZIP_ETDEFLBUF = -12    '' cannot flush tdefl buffer
const ZIP_ECRTHDR = -13      '' cannot create entry header
const ZIP_EWRTHDR = -14      '' cannot write entry header
const ZIP_EWRTDIR = -15      '' cannot write to central dir
const ZIP_EOPNFILE = -16     '' cannot open file
const ZIP_EINVENTTYPE = -17  '' invalid entry type
const ZIP_EMEMNOALLOC = -18  '' extracting data using no memory allocation
const ZIP_ENOFILE = -19      '' file not found
const ZIP_ENOPERM = -20      '' no permission
const ZIP_EOOMEM = -21       '' out of memory
const ZIP_EINVZIPNAME = -22  '' invalid zip archive name
const ZIP_EMKDIR = -23       '' make dir error
const ZIP_ESYMLINK = -24     '' symlink error
const ZIP_ECLSZIP = -25      '' close archive error
const ZIP_ECAPSIZE = -26     '' capacity size too small
const ZIP_EFSEEK = -27       '' fseek error
const ZIP_EFREAD = -28       '' fread error
const ZIP_EFWRITE = -29      '' fwrite error
const ZIP_ERINIT = -30       '' cannot initialize reader
const ZIP_EWINIT = -31       '' cannot initialize writer
const ZIP_EWRINIT = -32      '' cannot initialize writer from reader
const ZIP_EINVAL = -33       '' invalid argument
const ZIP_ENORITER = -34     '' cannot initialize reader iterator
const ZIP_ECHKDIR = -35      '' check dir error path exists but is not directory
const ZIP_EPASSWD = -36      '' wrong password or password required
const ZIP_NERRORS = 37       '' number of error codes

'' arhiva (tip opac)
type zip_t as zip_t_

'' apelul invers al lui zip_entry_extract: intoarce numarul de octeti consumati
type zip_entry_extract_callback as function cdecl(byval arg as any ptr, byval offset as ulongint, _
    byval data_ as const any ptr, byval size as uinteger) as uinteger

'' apelul invers al lui zip_extract / zip_stream_extract: o valoare negativa opreste extragerea
type zip_extract_callback as function cdecl(byval filename as const zstring ptr, byval arg as any ptr) as long

declare function zip_strerror(byval errnum as long) as const zstring ptr

declare function zip_open(byval zipname as const zstring ptr, byval level as long, byval mode as byte) as zip_t ptr
declare function zip_openwitherror(byval zipname as const zstring ptr, byval level as long, byval mode as byte, _
    byval errnum as long ptr) as zip_t ptr
declare function zip_open_with_password(byval zipname as const zstring ptr, byval level as long, _
    byval mode as byte, byval password as const zstring ptr) as zip_t ptr
declare function zip_open_with_password_and_error(byval zipname as const zstring ptr, byval level as long, _
    byval mode as byte, byval password as const zstring ptr, byval errnum as long ptr) as zip_t ptr
declare sub zip_close(byval zip as zip_t ptr)
declare function zip_is64(byval zip as zip_t ptr) as long
declare function zip_offset(byval zip as zip_t ptr, byval offset as ulongint ptr) as long

declare function zip_entry_open(byval zip as zip_t ptr, byval entryname as const zstring ptr) as long
declare function zip_entry_opencasesensitive(byval zip as zip_t ptr, byval entryname as const zstring ptr) as long
declare function zip_entry_openbyindex(byval zip as zip_t ptr, byval index as uinteger) as long
declare function zip_entry_close(byval zip as zip_t ptr) as long
declare function zip_entry_name(byval zip as zip_t ptr) as const zstring ptr
declare function zip_entry_index(byval zip as zip_t ptr) as integer
declare function zip_entry_isdir(byval zip as zip_t ptr) as long
declare function zip_entry_issymlink(byval zip as zip_t ptr) as long
declare function zip_entry_size(byval zip as zip_t ptr) as ulongint
declare function zip_entry_uncomp_size(byval zip as zip_t ptr) as ulongint
declare function zip_entry_comp_size(byval zip as zip_t ptr) as ulongint
declare function zip_entry_crc32(byval zip as zip_t ptr) as ulong
declare function zip_entry_dir_offset(byval zip as zip_t ptr) as ulongint
declare function zip_entry_header_offset(byval zip as zip_t ptr) as ulongint

declare function zip_entry_write(byval zip as zip_t ptr, byval buf as const any ptr, byval bufsize as uinteger) as long
declare function zip_entry_fwrite(byval zip as zip_t ptr, byval filename as const zstring ptr) as long

declare function zip_entry_read(byval zip as zip_t ptr, byval buf as any ptr ptr, byval bufsize as uinteger ptr) as integer
declare function zip_entry_noallocread(byval zip as zip_t ptr, byval buf as any ptr, byval bufsize as uinteger) as integer
declare function zip_entry_noallocreadwithoffset(byval zip as zip_t ptr, byval offset as uinteger, _
    byval size as uinteger, byval buf as any ptr) as integer
declare function zip_entry_fread(byval zip as zip_t ptr, byval filename as const zstring ptr) as long
declare function zip_entry_extract(byval zip as zip_t ptr, byval on_extract as zip_entry_extract_callback, _
    byval arg as any ptr) as long

declare function zip_entries_total(byval zip as zip_t ptr) as integer
declare function zip_entries_delete(byval zip as zip_t ptr, byval entries as zstring const ptr ptr, _
    byval len_ as uinteger) as integer
declare function zip_entries_deletebyindex(byval zip as zip_t ptr, byval entries as uinteger ptr, _
    byval len_ as uinteger) as integer

declare function zip_stream_extract(byval stream as const any ptr, byval size as uinteger, _
    byval dir_ as const zstring ptr, byval on_extract as zip_extract_callback, byval arg as any ptr) as long
declare function zip_stream_open(byval stream as const any ptr, byval size as uinteger, byval level as long, _
    byval mode as byte) as zip_t ptr
declare function zip_stream_open_with_password(byval stream as const any ptr, byval size as uinteger, _
    byval level as long, byval mode as byte, byval password as const zstring ptr) as zip_t ptr
declare function zip_stream_openwitherror(byval stream as const any ptr, byval size as uinteger, _
    byval level as long, byval mode as byte, byval errnum as long ptr) as zip_t ptr
declare function zip_stream_copy(byval zip as zip_t ptr, byval buf as any ptr ptr, byval bufsize as uinteger ptr) as integer
declare sub zip_stream_close(byval zip as zip_t ptr)

declare function zip_cstream_open(byval stream as FILE ptr, byval level as long, byval mode as byte) as zip_t ptr
declare function zip_cstream_openwitherror(byval stream as FILE ptr, byval level as long, byval mode as byte, _
    byval errnum as long ptr) as zip_t ptr
declare sub zip_cstream_close(byval zip as zip_t ptr)

declare function zip_create(byval zipname as const zstring ptr, byval filenames as const zstring ptr ptr, _
    byval len_ as uinteger) as long
declare function zip_extract(byval zipname as const zstring ptr, byval dir_ as const zstring ptr, _
    byval on_extract_entry as zip_extract_callback, byval arg as any ptr) as long

end extern
