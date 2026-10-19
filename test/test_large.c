#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <zip.h>

#include "minunit.h"

#if defined(_WIN32) || defined(_WIN64)
#include <io.h>

#define MKTEMP _mktemp
#define UNLINK _unlink
#define STAT64 _stat64
#define STAT64_STRUCT _stat64
#else
#define MKTEMP mkstemp
#define UNLINK unlink
#define STAT64 stat
#define STAT64_STRUCT stat
#endif

// Archives past 4 GB. Each test writes 4 GB to the current directory, so they
// run only with ZIP_TEST_LARGE=1 and pass without doing anything otherwise.

#define GB4 4294967296ull
#define CHUNK (1u << 20)

static unsigned char chunk[CHUNK];

static int large_enabled(void) {
  const char *e = getenv("ZIP_TEST_LARGE");
  return e && strcmp(e, "1") == 0;
}

static unsigned long long file_size(const char *name) {
  struct STAT64_STRUCT st;
  if (STAT64(name, &st) != 0) {
    return 0;
  }
  return (unsigned long long)st.st_size;
}

// writes size bytes into the open entry, 1 MB at a time, each chunk stamped
// with its index
static int write_large(struct zip_t *zip, unsigned long long size) {
  unsigned long long k = 0;
  while (size > 0) {
    size_t n = size < CHUNK ? (size_t)size : CHUNK;
    memcpy(chunk, &k, sizeof(k));
    if (zip_entry_write(zip, chunk, n) != 0) {
      return -1;
    }
    size -= n;
    ++k;
  }
  return 0;
}

static int write_small(struct zip_t *zip, const char *name, const char *data) {
  int err = zip_entry_open(zip, name);
  if (err == 0) {
    err = zip_entry_write(zip, data, strlen(data));
  }
  if (zip_entry_close(zip) != 0 && err == 0) {
    err = -1;
  }
  return err;
}

static int read_small(struct zip_t *zip, const char *name, const char *data) {
  char *buf = NULL;
  size_t size = 0;
  int ok;
  if (zip_entry_open(zip, name) != 0) {
    return 0;
  }
  ok = zip_entry_read(zip, (void **)&buf, &size) == (ssize_t)strlen(data) &&
       memcmp(buf, data, size) == 0;
  free(buf);
  zip_entry_close(zip);
  return ok;
}

// stored entry of 4 GB + 3 bytes, then a small entry, in a zip64 archive
static void check_large_archive(const char *name) {
  struct zip_t *zip;

  mu_check(file_size(name) > GB4);
  zip = zip_open(name, 0, 'r');
  mu_check(zip != NULL);
  mu_assert_int_eq(1, zip_is64(zip));
  mu_assert_int_eq(2, (int)zip_entries_total(zip));
  mu_assert_int_eq(0, zip_entry_open(zip, "big.bin"));
  mu_check(zip_entry_size(zip) == GB4 + 3);
  mu_check(zip_entry_comp_size(zip) == GB4 + 3);
  zip_entry_close(zip);
  mu_assert_int_eq(0, zip_entry_open(zip, "after.txt"));
  mu_check(zip_entry_header_offset(zip) > GB4);
  zip_entry_close(zip);
  mu_check(read_small(zip, "after.txt", "after 4 GB"));
  zip_close(zip);
}

MU_TEST(test_large_archive_not_truncated) {
  // zip_close truncates the file to the archive size; with MinGW's 32-bit
  // ftruncate an archive past 4 GB was cut to its size modulo 2^32, and every
  // add had reported success
  char name[L_tmpnam + 1] = {0};
  struct zip_t *zip;

  if (!large_enabled()) {
    return;
  }
  strncpy(name, "l-XXXXXX\0", L_tmpnam);
  MKTEMP(name);
  zip = zip_open(name, 0, 'w');
  mu_check(zip != NULL);
  mu_assert_int_eq(0, zip_entry_open(zip, "big.bin"));
  mu_assert_int_eq(0, write_large(zip, GB4 + 3));
  mu_assert_int_eq(0, zip_entry_close(zip));
  mu_assert_int_eq(0, write_small(zip, "after.txt", "after 4 GB"));
  zip_close(zip);

  check_large_archive(name);
  UNLINK(name);
}

MU_TEST(test_large_header_past_4gb_without_zip64) {
  // in an archive written without zip64 ('w' - 64), an entry whose local
  // header starts past 4 GB was refused by zip_entry_close (ZIP_EWRTDIR):
  // its offset fits only in the zip64 extra field. The archive now switches
  // to zip64 there, as miniz's own mz_zip_writer_add_* do.
  char name[L_tmpnam + 1] = {0};
  struct zip_t *zip;

  if (!large_enabled()) {
    return;
  }
  strncpy(name, "l-XXXXXX\0", L_tmpnam);
  MKTEMP(name);
  zip = zip_open(name, 0, 'w' - 64);
  mu_check(zip != NULL);
  mu_assert_int_eq(0, zip_entry_open(zip, "big.bin"));
  mu_assert_int_eq(0, write_large(zip, GB4 + 3));
  mu_assert_int_eq(0, zip_entry_close(zip));
  mu_assert_int_eq(0, write_small(zip, "after.txt", "after 4 GB"));
  zip_close(zip);

  check_large_archive(name);
  UNLINK(name);
}

MU_TEST_SUITE(test_large_suite) {
  if (!large_enabled()) {
    printf("test_large: skipped (set ZIP_TEST_LARGE=1, needs 5 GB free)\n");
  }
  MU_RUN_TEST(test_large_archive_not_truncated);
  MU_RUN_TEST(test_large_header_past_4gb_without_zip64);
}

#define UNUSED(x) (void)x

int main(int argc, char *argv[]) {
  UNUSED(argc);
  UNUSED(argv);

  MU_RUN_SUITE(test_large_suite);
  MU_REPORT();
  return MU_EXIT_CODE;
}
