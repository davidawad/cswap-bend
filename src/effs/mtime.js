// Dirlock
// =======

function dirlock_mtime(path) {
  try {
    return io_done(Math.floor(require("fs").statSync(path).mtimeMs / 1000) >>> 0);
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(Dirlock.mtime), dirlock_mtime);
