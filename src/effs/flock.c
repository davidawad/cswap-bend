// Flock
// =====

#include <sys/file.h>

// One non-blocking flock(LOCK_EX) on the descriptor of a File. word is 1 when
// the lock is now held, 0 when another holder has it; any other errno fails.
// flock is cheap and never waits with LOCK_NB, but it runs on a helper thread
// like the other file effects.
static void flock_try_call(IoWork* w) {
  int n = flock((int)w->hand, LOCK_EX | LOCK_NB);
  if (n == 0) {
    w->code = 0;
    w->word = 1;
  } else if (errno == EWOULDBLOCK) {
    w->code = 0;
    w->word = 0;
  } else {
    io_sys_end(w, n);
  }
}

// The File is handed back, still open: the lock lives as long as the
// descriptor and goes with File.close.
static Term flock_try_pack(Env e, IoWork* w) {
  return io_tup(e, io_hand(w->hand), io_res(e, w, w->word));
}

Term flock_try_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  return io_work(w, flock_try_call, flock_try_pack);
}

static void __attribute__((constructor)) flock_try_use(void) {
  io_eff(CID(Flock.try), flock_try_run);
}
