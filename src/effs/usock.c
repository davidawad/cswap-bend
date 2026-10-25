// Usock
// =====

#include <sys/un.h>
#include <sys/stat.h>
#include <signal.h>

// The path of the socket this process listens on, so the signal handler can
// remove it. One listener per process.
static char usock_path[sizeof(((struct sockaddr_un*)0)->sun_path)];
static volatile sig_atomic_t usock_bound = 0;

// SIGTERM, SIGINT, SIGHUP: remove the socket file and leave with status 0.
// Only async-signal-safe calls.
static void usock_stop(int sig) {
  (void)sig;
  if (usock_bound) {
    unlink(usock_path);
  }
  _exit(0);
}

static void usock_handlers(void) {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = usock_stop;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGTERM, &sa, NULL);
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGHUP, &sa, NULL);
  // A client that goes away mid-reply must not kill the server.
  signal(SIGPIPE, SIG_IGN);
}

// A stale socket file may be replaced; anything else at the path is not ours.
static int usock_clear(const char* path) {
  struct stat st;
  if (lstat(path, &st) != 0) {
    return errno == ENOENT ? 0 : -1;
  }
  if (!S_ISSOCK(st.st_mode)) {
    errno = EEXIST;
    return -1;
  }
  return unlink(path);
}

// listen(path): a non-blocking stream socket bound to the unix path, mode
// 0600 from the moment it exists (umask 0177 around bind, then chmod). The
// Listener answers TCP.accept like a TCP one.
Term usock_listen_run(Env e, Term* f, IoWork* w) {
  u64 len;
  char* path = io_cstr(e, f[0], &len);
  struct sockaddr_un at;
  size_t n = path ? strlen(path) : 0;
  if (!path || io_nul(path, len) || n == 0 || n >= sizeof(at.sun_path)) {
    free(path);
    return io_fail(e, EINVAL, NULL);
  }
  memset(&at, 0, sizeof(at));
  at.sun_family = AF_UNIX;
  memcpy(at.sun_path, path, n + 1);
  if (usock_clear(path) != 0) {
    uint32_t code = (uint32_t)errno;
    free(path);
    return io_fail(e, code, NULL);
  }
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    uint32_t code = (uint32_t)errno;
    free(path);
    return io_fail(e, code, NULL);
  }
  mode_t old = umask(0177);
  int bound = bind(fd, (struct sockaddr*)&at, sizeof(at));
  umask(old);
  if (bound < 0 || chmod(path, 0600) < 0 || listen(fd, 16) < 0
    || fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0) {
    uint32_t code = (uint32_t)errno;
    close(fd);
    if (bound == 0) {
      unlink(path);
    }
    free(path);
    return io_fail(e, code, NULL);
  }
  memcpy(usock_path, path, n + 1);
  usock_bound = 1;
  usock_handlers();
  free(path);
  return io_done(e, io_hand(fd));
}

static void __attribute__((constructor)) usock_listen_use(void) {
  io_eff(CID(Usock.listen), usock_listen_run);
}
