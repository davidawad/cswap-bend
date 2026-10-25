// Clock
// =====

Term clock_now_s_run(Env e, Term* f, IoWork* w) {
  return (Term)(uint32_t)time(NULL);
}

static void __attribute__((constructor)) clock_now_s_use(void) {
  io_eff(CID(Clock.now_s), clock_now_s_run);
}
