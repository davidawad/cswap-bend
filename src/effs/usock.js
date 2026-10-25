// Usock
// =====

// The JavaScript lane has no unix-socket server: Node and Bun give no
// descriptor to hand to TCP.accept. ENOSYS is 78 on mac and 38 elsewhere.
function usock_listen(path) {
  return io_fail(process.platform === "darwin" ? 78 : 38);
}

io_eff(CID(Usock.listen), usock_listen);
