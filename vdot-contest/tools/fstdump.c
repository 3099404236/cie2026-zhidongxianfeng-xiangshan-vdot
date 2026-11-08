/* fstdump: print value changes of selected signals from an FST waveform.
 *
 *   fstdump <wave.fst> [-l] [-t t0 t1] pattern...
 *
 *   -l        list matching signal names only
 *   -t a b    only report changes with a <= time <= b
 *   pattern   substring that must occur in the full hierarchical name;
 *             several patterns are OR-ed.
 *
 * Output lines: "<time> <full.signal.name> <value-bits>"
 * Build: gcc -O2 -I$VI -DFST_CONFIG_INCLUDE='"fst_config.h"' fstdump.c \
 *            $VI/fstapi.c $VI/lz4.c $VI/fastlz.c -lz -o fstdump
 *        (VI=/usr/share/verilator/include/gtkwave, shipped with Verilator)
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fstapi.h"

#define MAX_SIG 4096

static char *names[MAX_SIG];
static fstHandle handles[MAX_SIG];
static int nsig;
static char **name_of; /* indexed by handle */
static uint64_t t_lo = 0, t_hi = UINT64_MAX;

static void cb(void *user, uint64_t time, fstHandle h, const unsigned char *val) {
  (void)user;
  if (time < t_lo || time > t_hi || !name_of[h]) return;
  printf("%llu %s %s\n", (unsigned long long)time, name_of[h], (const char *)val);
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s wave.fst [-l] [-t t0 t1] pattern...\n", argv[0]);
    return 2;
  }
  void *ctx = fstReaderOpen(argv[1]);
  if (!ctx) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
  int list = 0, first = 2;
  while (first < argc && argv[first][0] == '-') {
    if (!strcmp(argv[first], "-l")) { list = 1; first++; }
    else if (!strcmp(argv[first], "-t") && first + 2 < argc) {
      t_lo = strtoull(argv[first + 1], 0, 0); t_hi = strtoull(argv[first + 2], 0, 0); first += 3;
    } else break;
  }
  uint64_t maxh = fstReaderGetMaxHandle(ctx);
  name_of = calloc(maxh + 1, sizeof(char *));

  char scope[4096] = "";
  size_t depth_len[512];
  int depth = 0;
  struct fstHier *hier;
  while ((hier = fstReaderIterateHier(ctx))) {
    if (hier->htyp == FST_HT_SCOPE) {
      depth_len[depth++] = strlen(scope);
      if (scope[0]) strcat(scope, ".");
      strcat(scope, hier->u.scope.name);
    } else if (hier->htyp == FST_HT_UPSCOPE) {
      if (depth > 0) scope[depth_len[--depth]] = 0;
    } else if (hier->htyp == FST_HT_VAR) {
      char full[8192];
      snprintf(full, sizeof full, "%s.%s", scope, hier->u.var.name);
      int match = 0;
      for (int i = first; i < argc; i++)
        if (strstr(full, argv[i])) { match = 1; break; }
      if (!match || name_of[hier->u.var.handle]) continue;
      name_of[hier->u.var.handle] = strdup(full);
      if (nsig < MAX_SIG) { names[nsig] = name_of[hier->u.var.handle]; handles[nsig++] = hier->u.var.handle; }
      if (list) printf("%s (%u bits)\n", full, hier->u.var.length);
    }
  }
  if (!list) {
    fstReaderClrFacProcessMaskAll(ctx);
    for (int i = 0; i < nsig; i++) fstReaderSetFacProcessMask(ctx, handles[i]);
    fstReaderIterBlocks(ctx, cb, NULL, NULL);
  }
  fstReaderClose(ctx);
  return 0;
}
