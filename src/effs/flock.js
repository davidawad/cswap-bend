// Flock
// =====

// The JavaScript lane has no flock: Node and Bun expose none, and a lock that
// silently did nothing would be worse than a failure. ENOSYS is 78 on mac and
// 38 elsewhere.
function flock_try(file) {
  return io_tup(file, io_fail(process.platform === "darwin" ? 78 : 38));
}

io_eff(CID(Flock.try), flock_try);
