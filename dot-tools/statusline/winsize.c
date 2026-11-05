#include <sys/ioctl.h>

// Returns the column count of the terminal on `fd`, or 0 when it is not a terminal.
int agent_hooks_terminal_columns(int fd) {
  struct winsize size;
  if (ioctl(fd, TIOCGWINSZ, &size) != 0) {
    return 0;
  }
  return size.ws_col;
}
