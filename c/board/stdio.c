#include <stdio.h>

#include "sl_debug_swo.h"
#include "sl_iostream_debug.h"
#include "sl_iostream_swo.h"

static int miso_putc(char c, FILE *file)
{
    (void)file;
#if (MISO_APPLICATION)
    if (taskSCHEDULER_RUNNING == xTaskGetSchedulerState())
    {
        usb_write_char(c);
    }
    else
    {
        (void)sl_iostream_putchar(SL_IOSTREAM_STDOUT, c);
    }
#else
    (void)sl_iostream_putchar(SL_IOSTREAM_STDOUT, c);
#endif

    return 1;
}

static int miso_getc(FILE *file)
{
    char c = EOF;
    (void)file;
    (void)sl_iostream_getchar(SL_IOSTREAM_STDIN, &c);

    return c;
}

static int miso_flush(FILE *file)
{
    (void)file;

    return 0;
}

static FILE __stdio = FDEV_SETUP_STREAM(miso_putc, miso_getc, miso_flush, _FDEV_SETUP_RW);

#ifdef __strong_reference
#define STDIO_ALIAS(x) __strong_reference(stdin, x);
#else
#define STDIO_ALIAS(x) FILE *const x = &__stdio;
#endif

FILE *const stdin = &__stdio;
STDIO_ALIAS(stdout);
STDIO_ALIAS(stderr);

int write(int handle, const unsigned char *buffer, size_t size)
{
    (void)handle;

    for (size_t i = 0; i < size; i++)
    {
        (void)sl_iostream_putchar(SL_IOSTREAM_STDOUT, buffer[i]);
    }

    return size;
}

char __arm32_tls_tcb_offset = 8;