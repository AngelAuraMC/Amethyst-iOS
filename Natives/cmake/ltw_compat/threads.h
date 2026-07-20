#ifndef LTW_COMPAT_THREADS_H
#define LTW_COMPAT_THREADS_H

/* AppleClang supports thread_local as a built-in - no header needed. */
/* This compat header prevents inclusion errors on iOS where <threads.h>
   is not provided by the system SDK. */

#define thread_local _Thread_local

#endif /* LTW_COMPAT_THREADS_H */
