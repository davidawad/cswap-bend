// Dirlock
// =======

#include <sys/stat.h>

// The modification time of a path in whole seconds (stat follows symlinks).
static void dirlock_mtime_call(IoWork* w) {
  struct stat st;
  int n = stat(w->data, &st);
  io_sys_end(w, n);
  if (n == 0) {
    w->word = (u32)st.st_mtime;
  }
}

static Term dirlock_mtime_pack(Env e, IoWork* w) {
  free(w->data);
  return io_res(e, w, w->word);
}

Term dirlock_mtime_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  if (io_nul(w->data, w->size)) {
    w->code = EILSEQ;
    return dirlock_mtime_pack(e, w);
  }
  return io_work(w, dirlock_mtime_call, dirlock_mtime_pack);
}

static void __attribute__((constructor)) dirlock_mtime_use(void) {
  io_eff(CID(Dirlock.mtime), dirlock_mtime_run);
}
