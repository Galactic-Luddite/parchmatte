#include "WindowListBridge.h"

#include <stdint.h>

static PMWindowQueryStatus PMNearestWindowInRawArray(
    CFArrayRef _Nullable windowList,
    CGWindowID * _Nonnull nearestWindow
) {
    *nearestWindow = kCGNullWindowID;
    if (windowList == NULL) {
        return PMWindowQueryFailed;
    }

    CFIndex count = CFArrayGetCount(windowList);
    if (count == 0) {
        return PMWindowQueryEmpty;
    }

    const void *rawWindowID = CFArrayGetValueAtIndex(windowList, count - 1);
    *nearestWindow = (CGWindowID)(uintptr_t)rawWindowID;
    return PMWindowQueryFound;
}

PMWindowQueryStatus PMNearestWindowAboveWithQuery(
    CGWindowID relativeToWindow,
    CGWindowID * _Nonnull nearestWindow,
    PMWindowListCreateFunction _Nonnull createWindowList
) {
    CFArrayRef windowList = createWindowList(
        kCGWindowListOptionOnScreenAboveWindow,
        relativeToWindow
    );
    PMWindowQueryStatus status = PMNearestWindowInRawArray(windowList, nearestWindow);
    if (windowList != NULL) {
        CFRelease(windowList);
    }
    return status;
}

PMWindowQueryStatus PMNearestWindowAbove(
    CGWindowID relativeToWindow,
    CGWindowID * _Nonnull nearestWindow
) {
    return PMNearestWindowAboveWithQuery(relativeToWindow, nearestWindow, CGWindowListCreate);
}
