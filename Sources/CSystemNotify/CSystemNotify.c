#include "CSystemNotify.h"
#include <notify.h>

uint32_t MSNotifyPost(const char *name) { return notify_post(name); }

uint32_t MSNotifyRegisterDispatch(const char *name, int *outToken,
                                  dispatch_queue_t queue,
                                  void (^handler)(int token)) {
  return notify_register_dispatch(name, outToken, queue, handler);
}

uint32_t MSNotifyCancel(int token) { return notify_cancel(token); }
