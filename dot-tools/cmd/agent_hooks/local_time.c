#include <stdint.h>
#include <time.h>

// MoonBit's core has no time zone database, so libc formats the local time, as Python's time.strftime does.
// Returns the length written into buffer, or 0 when the time cannot be converted.
int32_t agent_hooks_local_time(int64_t seconds, uint8_t *buffer, int32_t size) {
  time_t at = (time_t)seconds;
  struct tm local;
  // localtime_r need not read TZ again; tzset makes a changed TZ count, as localtime does.
  tzset();
  // Fall back to UTC rather than log an empty time.
  if (localtime_r(&at, &local) == NULL && gmtime_r(&at, &local) == NULL) {
    return 0;
  }
  return (int32_t)strftime((char *)buffer, (size_t)size, "%Y-%m-%dT%H:%M:%S%z", &local);
}
