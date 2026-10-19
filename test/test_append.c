#include <stdio.h>
#include <stdlib.h>

#include <zip.h>

#include "minunit.h"

#if defined(_WIN32) || defined(_WIN64)
#include <io.h>

#define MKTEMP _mktemp
#define UNLINK _unlink
#else
#define MKTEMP mkstemp
#define UNLINK unlink
#endif

static char ZIPNAME[L_tmpnam + 1] = {0};
static int total_entries = 0;

#define TESTDATA1 "Some test data 1...\0"

void test_setup(void) {
  strncpy(ZIPNAME, "z-XXXXXX\0", L_tmpnam);
  MKTEMP(ZIPNAME);

  struct zip_t *zip = zip_open(ZIPNAME, ZIP_DEFAULT_COMPRESSION_LEVEL, 'w');

  zip_entry_open(zip, "test/test-1.txt");
  zip_entry_write(zip, TESTDATA1, strlen(TESTDATA1));
  zip_entry_close(zip);
  ++total_entries;

  zip_close(zip);
}

void test_teardown(void) { UNLINK(ZIPNAME); }

#define TESTDATA2 "Some test data 2...\0"
#define CRC32DATA2 2532008468

MU_TEST(test_append) {
  struct zip_t *zip = zip_open(ZIPNAME, ZIP_DEFAULT_COMPRESSION_LEVEL, 'a');
  mu_check(zip != NULL);

  mu_assert_int_eq(0, zip_entry_open(zip, "test\\test-2.txt"));
  mu_assert_int_eq(0, strcmp(zip_entry_name(zip), "test/test-2.txt"));
  mu_assert_int_eq(total_entries, zip_entry_index(zip));
  mu_assert_int_eq(0, zip_entry_write(zip, TESTDATA2, strlen(TESTDATA2)));
  mu_assert_int_eq(strlen(TESTDATA2), zip_entry_size(zip));
  mu_check(CRC32DATA2 == zip_entry_crc32(zip));
  mu_assert_int_eq(0, zip_entry_close(zip));
  ++total_entries;
  zip_close(zip);

  zip = zip_open(ZIPNAME, ZIP_DEFAULT_COMPRESSION_LEVEL, 'a');
  mu_assert_int_eq(0, zip_entry_open(zip, "test\\empty/"));
  mu_assert_int_eq(0, strcmp(zip_entry_name(zip), "test/empty/"));
  mu_assert_int_eq(0, zip_entry_size(zip));
  mu_assert_int_eq(0, zip_entry_crc32(zip));
  mu_assert_int_eq(total_entries, zip_entry_index(zip));
  mu_assert_int_eq(0, zip_entry_close(zip));
  ++total_entries;
  zip_close(zip);

  zip = zip_open(ZIPNAME, ZIP_DEFAULT_COMPRESSION_LEVEL, 'a');
  mu_assert_int_eq(0, zip_entry_open(zip, "empty/"));
  mu_assert_int_eq(0, strcmp(zip_entry_name(zip), "empty/"));
  mu_assert_int_eq(0, zip_entry_size(zip));
  mu_assert_int_eq(0, zip_entry_crc32(zip));
  mu_assert_int_eq(total_entries, zip_entry_index(zip));
  mu_assert_int_eq(0, zip_entry_close(zip));
  ++total_entries;

  mu_assert_int_eq(0, zip_entry_open(zip, "dotfiles/.test"));
  mu_assert_int_eq(0, strcmp(zip_entry_name(zip), "dotfiles/.test"));
  mu_assert_int_eq(0, zip_entry_size(zip));
  mu_assert_int_eq(0, zip_entry_crc32(zip));
  mu_assert_int_eq(0, zip_entry_write(zip, TESTDATA2, strlen(TESTDATA2)));
  mu_assert_int_eq(strlen(TESTDATA2), zip_entry_size(zip));
  mu_check(CRC32DATA2 == zip_entry_crc32(zip));
  mu_assert_int_eq(total_entries, zip_entry_index(zip));
  mu_assert_int_eq(0, zip_entry_close(zip));
  ++total_entries;

  mu_assert_int_eq(total_entries, zip_entries_total(zip));

  zip_close(zip);
}

// writes entries "f/<first>.txt" .. "f/<last>.txt" with their number as data
static int append_numbered(struct zip_t *zip, int first, int last) {
  char name[32], data[16];
  int i;
  for (i = first; i <= last; ++i) {
    snprintf(name, sizeof(name), "f/%d.txt", i);
    snprintf(data, sizeof(data), "%d", i);
    if (zip_entry_open(zip, name) != 0 ||
        zip_entry_write(zip, data, strlen(data)) != 0 ||
        zip_entry_close(zip) != 0) {
      return -1;
    }
  }
  return 0;
}

static int read_numbered(struct zip_t *zip, int i) {
  char name[32], data[16];
  char *buf = NULL;
  size_t size = 0;
  int ok;
  snprintf(name, sizeof(name), "f/%d.txt", i);
  snprintf(data, sizeof(data), "%d", i);
  if (zip_entry_open(zip, name) != 0) {
    return 0;
  }
  ok = zip_entry_read(zip, (void **)&buf, &size) == (ssize_t)strlen(data) &&
       memcmp(buf, data, size) == 0;
  free(buf);
  zip_entry_close(zip);
  return ok;
}

MU_TEST(test_append_past_65535_entries_without_zip64) {
  // an archive in the classic format (no zip64 end of central directory)
  // that grows past 65535 entries must switch to zip64 when it is finalized.
  // zip.c writes entry headers itself, bypassing miniz's own switch, so
  // finalize failed with MZ_ZIP_TOO_MANY_FILES: appending left the old central
  // directory overwritten and no new one, and the archive could not be opened.
  char name[L_tmpnam + 1] = {0};
  struct zip_t *zip;
  void *buf = NULL;
  size_t size = 0;

  strncpy(name, "c-XXXXXX\0", L_tmpnam);
  MKTEMP(name);
  // 'w' - 64 writes without the zip64 flag
  zip = zip_open(name, ZIP_DEFAULT_COMPRESSION_LEVEL, 'w' - 64);
  mu_check(zip != NULL);
  mu_assert_int_eq(0, append_numbered(zip, 0, 65533));
  zip_close(zip);

  zip = zip_open(name, 0, 'r');
  mu_check(zip != NULL);
  mu_assert_int_eq(65534, (int)zip_entries_total(zip));
  mu_assert_int_eq(0, zip_is64(zip));
  zip_close(zip);

  zip = zip_open(name, ZIP_DEFAULT_COMPRESSION_LEVEL, 'a');
  mu_check(zip != NULL);
  mu_assert_int_eq(0, append_numbered(zip, 65534, 65539));
  zip_close(zip);

  zip = zip_open(name, 0, 'r');
  mu_check(zip != NULL);
  mu_assert_int_eq(65540, (int)zip_entries_total(zip));
  mu_assert_int_eq(1, zip_is64(zip));
  mu_check(read_numbered(zip, 0));
  mu_check(read_numbered(zip, 65535));
  mu_check(read_numbered(zip, 65539));
  zip_close(zip);
  UNLINK(name);

  // the same written in one go, in memory
  zip = zip_stream_open(NULL, 0, ZIP_DEFAULT_COMPRESSION_LEVEL, 'w' - 64);
  mu_check(zip != NULL);
  mu_assert_int_eq(0, append_numbered(zip, 0, 65539));
  mu_check(zip_stream_copy(zip, &buf, &size) > 0);
  zip_stream_close(zip);

  zip = zip_stream_open((const char *)buf, size, 0, 'r');
  mu_check(zip != NULL);
  mu_assert_int_eq(65540, (int)zip_entries_total(zip));
  mu_check(read_numbered(zip, 65539));
  zip_stream_close(zip);
  free(buf);
}

MU_TEST_SUITE(test_append_suite) {
  MU_SUITE_CONFIGURE(&test_setup, &test_teardown);

  MU_RUN_TEST(test_append);
  MU_RUN_TEST(test_append_past_65535_entries_without_zip64);
}

#define UNUSED(x) (void)x

int main(int argc, char *argv[]) {
  UNUSED(argc);
  UNUSED(argv);

  MU_RUN_SUITE(test_append_suite);
  MU_REPORT();
  return MU_EXIT_CODE;
}
