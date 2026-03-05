// macOS Private API 桥接头
// 用于窗口层级控制

#ifndef CGSPrivate_h
#define CGSPrivate_h

#include <CoreGraphics/CoreGraphics.h>

typedef int CGSConnectionID;

// 获取默认连接
extern CGSConnectionID CGSMainConnectionID(void);

// 设置窗口层级
extern CGError CGSSetWindowLevel(CGSConnectionID cid, CGWindowID wid, CGWindowLevel level);

// 获取窗口层级
extern CGError CGSGetWindowLevel(CGSConnectionID cid, CGWindowID wid, CGWindowLevel *level);

#endif /* CGSPrivate_h */
