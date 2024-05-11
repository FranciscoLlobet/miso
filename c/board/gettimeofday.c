
#include <sys/time.h>
// Gets called by time()

extern int gettimeofday(struct timeval *ptimeval, void *ptimezone);
/* implementing system time */
int gettimeofday(struct timeval *ptimeval, void *ptimezone)
{
    struct timezone *timezone_ptr = (struct timezone *)ptimezone;

    if (NULL != ptimeval)
    {
        ptimeval->tv_sec  = 0; //sl_sleeptimer_get_time();
        ptimeval->tv_usec = 0;
    }

    if (NULL != timezone_ptr)
    {
        timezone_ptr->tz_dsttime     = 0;
        timezone_ptr->tz_minuteswest = 0;
    }

    return 0;
}