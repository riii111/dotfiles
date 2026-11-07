#include <stdint.h>
#include <time.h>

// MoonBit's core has no time zone database, so the offset of local time comes from libc.
int32_t agent_hooks_utc_offset(int64_t seconds) {
  time_t at = (time_t)seconds;
  struct tm local;
  if (localtime_r(&at, &local) == NULL) {
    return 0;
  }
  return (int32_t)local.tm_gmtoff;
}
