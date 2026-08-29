#ifndef CSystemNotify_h
#define CSystemNotify_h

#include <dispatch/dispatch.h>
#include <stdint.h>

uint32_t MSNotifyPost(const char *name);
uint32_t MSNotifyRegisterDispatch(const char *name, int *outToken,
                                  dispatch_queue_t queue,
                                  void (^handler)(int token));
uint32_t MSNotifyCancel(int token);

#endif
