#include <stdio.h>
#include <string.h>

#include <zip.h>

#include "minunit.h"

#include <io.h>
#include <windows.h>

/* The DOS time of an entry is the local wall-clock time of the file's
 * modification time, with the daylight saving offset of that date, as other
 * zip tools and Windows Explorer read it. msvcrt.dll's _wstat and _wutime
 * apply the offset in effect today instead: a test on a January date and one
 * on a July date catch that on any day, in any time zone with DST */

#define ZIPNAME "dostime.zip"
#define SRCNAME "dostime-src.txt"
#define OUTDIR "dostime-out"
#define OUTNAME OUTDIR "/a.txt"

#define UNUSED(x) (void)x

/* 2020-<month>-02 03:04:06 */
static SYSTEMTIME wall_clock(WORD month) {
  SYSTEMTIME st;
  memset(&st, 0, sizeof(st));
  st.wYear = 2020;
  st.wMonth = month;
  st.wDay = 2;
  st.wHour = 3;
  st.wMinute = 4;
  st.wSecond = 6;
  return st;
}

static unsigned dos_time(WORD month) {
  SYSTEMTIME st = wall_clock(month);
  return (unsigned)((st.wHour << 11) | (st.wMinute << 5) | (st.wSecond >> 1));
}

static unsigned dos_date(WORD month) {
  SYSTEMTIME st = wall_clock(month);
  return (unsigned)(((st.wYear - 1980) << 9) | (st.wMonth << 5) | st.wDay);
}

static int set_mtime(const char *path, WORD month) {
  SYSTEMTIME local = wall_clock(month), utc;
  FILETIME ft;
  HANDLE h;
  int ok;
  if (!TzSpecificLocalTimeToSystemTime(NULL, &local, &utc) ||
      !SystemTimeToFileTime(&utc, &ft))
    return 0;
  h = CreateFileA(path, FILE_WRITE_ATTRIBUTES, 0, NULL, OPEN_EXISTING,
                  FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE)
    return 0;
  ok = SetFileTime(h, NULL, NULL, &ft) != 0;
  CloseHandle(h);
  return ok;
}

static int get_mtime(const char *path, SYSTEMTIME *local) {
  WIN32_FILE_ATTRIBUTE_DATA fad;
  SYSTEMTIME utc;
  return GetFileAttributesExA(path, GetFileExInfoStandard, &fad) &&
         FileTimeToSystemTime(&fad.ftLastWriteTime, &utc) &&
         SystemTimeToTzSpecificLocalTime(NULL, &utc, local);
}

static void put16(unsigned char *p, unsigned v) {
  p[0] = (unsigned char)(v & 0xFF);
  p[1] = (unsigned char)((v >> 8) & 0xFF);
}

static void put32(unsigned char *p, unsigned long v) {
  put16(p, (unsigned)(v & 0xFFFF));
  put16(p + 2, (unsigned)((v >> 16) & 0xFFFF));
}

static unsigned get16(const unsigned char *p) {
  return (unsigned)(p[0] | (p[1] << 8));
}

static unsigned long get32(const unsigned char *p) {
  return (unsigned long)get16(p) | ((unsigned long)get16(p + 2) << 16);
}

/* an archive with one empty stored entry "a.txt" and the given DOS time */
static int write_archive(WORD month) {
  unsigned char buf[30 + 5 + 46 + 5 + 22];
  unsigned char *lh = buf, *cd = buf + 35, *eocd = buf + 86;
  FILE *f;
  size_t n;

  memset(buf, 0, sizeof(buf));
  put32(lh, 0x04034b50UL);
  put16(lh + 4, 20);
  put16(lh + 10, dos_time(month));
  put16(lh + 12, dos_date(month));
  put16(lh + 26, 5);
  memcpy(lh + 30, "a.txt", 5);

  put32(cd, 0x02014b50UL);
  put16(cd + 4, 20);
  put16(cd + 6, 20);
  put16(cd + 12, dos_time(month));
  put16(cd + 14, dos_date(month));
  put16(cd + 28, 5);
  memcpy(cd + 46, "a.txt", 5);

  put32(eocd, 0x06054b50UL);
  put16(eocd + 8, 1);
  put16(eocd + 10, 1);
  put32(eocd + 12, 46 + 5);
  put32(eocd + 16, 30 + 5);

  f = fopen(ZIPNAME, "wb");
  if (!f)
    return 0;
  n = fwrite(buf, 1, sizeof(buf), f);
  fclose(f);
  return n == sizeof(buf);
}

/* DOS time and date from the central directory of a one-entry archive
 * without a comment */
static int read_dos_time(unsigned *time, unsigned *date) {
  unsigned char buf[1024];
  unsigned long cd_ofs;
  size_t n;
  FILE *f = fopen(ZIPNAME, "rb");
  if (!f)
    return 0;
  n = fread(buf, 1, sizeof(buf), f);
  fclose(f);
  if (n < 22 || get32(buf + n - 22) != 0x06054b50UL)
    return 0;
  cd_ofs = get32(buf + n - 22 + 16);
  if (cd_ofs + 46 > n || get32(buf + cd_ofs) != 0x02014b50UL)
    return 0;
  *time = get16(buf + cd_ofs + 12);
  *date = get16(buf + cd_ofs + 14);
  return 1;
}

void test_setup(void) {}

void test_teardown(void) {
  _unlink(OUTNAME);
  RemoveDirectoryA(OUTDIR);
  _unlink(SRCNAME);
  _unlink(ZIPNAME);
}

static void check_fwrite(WORD month) {
  struct zip_t *zip;
  unsigned time = 0, date = 0;
  FILE *f = fopen(SRCNAME, "wb");
  mu_check(f != NULL);
  fputs("dostime", f);
  fclose(f);
  mu_check(set_mtime(SRCNAME, month));

  zip = zip_open(ZIPNAME, ZIP_DEFAULT_COMPRESSION_LEVEL, 'w');
  mu_check(zip != NULL);
  mu_assert_int_eq(0, zip_entry_open(zip, "a.txt"));
  mu_assert_int_eq(0, zip_entry_fwrite(zip, SRCNAME));
  mu_assert_int_eq(0, zip_entry_close(zip));
  zip_close(zip);

  mu_check(read_dos_time(&time, &date));
  mu_assert_int_eq((int)dos_date(month), (int)date);
  mu_assert_int_eq((int)dos_time(month), (int)time);
}

static void check_extract(WORD month) {
  SYSTEMTIME expected = wall_clock(month), local;
  mu_check(write_archive(month));
  mu_check(CreateDirectoryA(OUTDIR, NULL));
  mu_assert_int_eq(0, zip_extract(ZIPNAME, OUTDIR, NULL, NULL));
  mu_check(get_mtime(OUTNAME, &local));
  mu_assert_int_eq(expected.wYear, local.wYear);
  mu_assert_int_eq(expected.wMonth, local.wMonth);
  mu_assert_int_eq(expected.wDay, local.wDay);
  mu_assert_int_eq(expected.wHour, local.wHour);
  mu_assert_int_eq(expected.wMinute, local.wMinute);
  mu_assert_int_eq(expected.wSecond, local.wSecond);
}

MU_TEST(test_fwrite_dostime_winter) { check_fwrite(1); }

MU_TEST(test_fwrite_dostime_summer) { check_fwrite(7); }

MU_TEST(test_extract_mtime_winter) { check_extract(1); }

MU_TEST(test_extract_mtime_summer) { check_extract(7); }

MU_TEST_SUITE(test_dostime_suite) {
  MU_SUITE_CONFIGURE(&test_setup, &test_teardown);

  MU_RUN_TEST(test_fwrite_dostime_winter);
  MU_RUN_TEST(test_fwrite_dostime_summer);
  MU_RUN_TEST(test_extract_mtime_winter);
  MU_RUN_TEST(test_extract_mtime_summer);
}

int main(int argc, char *argv[]) {
  UNUSED(argc);
  UNUSED(argv);

  MU_RUN_SUITE(test_dostime_suite);
  MU_REPORT();
  return MU_EXIT_CODE;
}
