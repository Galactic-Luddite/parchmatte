#ifndef WINDOW_LIST_BRIDGE_H
#define WINDOW_LIST_BRIDGE_H

#include <CoreGraphics/CGWindow.h>

typedef enum PMWindowQueryStatus {
    PMWindowQueryFailed = 0,
    PMWindowQueryEmpty = 1,
    PMWindowQueryFound = 2,
} PMWindowQueryStatus;

typedef CFArrayRef _Nullable (*PMWindowListCreateFunction)(
    CGWindowListOption option,
    CGWindowID relativeToWindow
);

PMWindowQueryStatus PMNearestWindowAbove(
    CGWindowID relativeToWindow,
    CGWindowID * _Nonnull nearestWindow
);

PMWindowQueryStatus PMNearestWindowAboveWithQuery(
    CGWindowID relativeToWindow,
    CGWindowID * _Nonnull nearestWindow,
    PMWindowListCreateFunction _Nonnull createWindowList
);

#endif
