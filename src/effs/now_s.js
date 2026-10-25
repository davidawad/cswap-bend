// Clock
// =====

function clock_now_s() {
  return Math.floor(Date.now() / 1000) >>> 0;
}

io_eff(CID(Clock.now_s), clock_now_s);
