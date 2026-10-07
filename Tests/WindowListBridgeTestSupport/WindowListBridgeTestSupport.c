#include "WindowListBridgeTestSupport.h"
#include "WindowListBridge.h"

static CFArrayRef testWindowList;

static CFArrayRef copyTestWindowList(CGWindowListOption option, CGWindowID relativeToWindow) {
    (void)option;
    (void)relativeToWindow;
    return testWindowList == NULL ? NULL : CFRetain(testWindowList);
}

static CFArrayRef makeRawWindowList(const CGWindowID *windowIDs, CFIndex count) {
    const void *values[count > 0 ? count : 1];
    for (CFIndex index = 0; index < count; index++) {
        values[index] = (const void *)(uintptr_t)windowIDs[index];
    }
    return CFArrayCreate(kCFAllocatorDefault, values, count, NULL);
}

static int runQuery(const CGWindowID *windowIDs, CFIndex count,
                    PMWindowQueryStatus expectedStatus, CGWindowID expectedID) {
    testWindowList = makeRawWindowList(windowIDs, count);
    CGWindowID actualID = UINT32_MAX;
    PMWindowQueryStatus status = PMNearestWindowAboveWithQuery(
        99, &actualID, copyTestWindowList
    );
    CFRelease(testWindowList);
    testWindowList = NULL;
    return status == expectedStatus && actualID == expectedID ? 0 : 1;
}

int PMRunWindowListBridgeTest(PMBridgeTestCase testCase) {
    switch (testCase) {
    case PMBridgeTestEmpty:
        return runQuery(NULL, 0, PMWindowQueryEmpty, kCGNullWindowID);
    case PMBridgeTestFailure: {
        CGWindowID actualID = UINT32_MAX;
        PMWindowQueryStatus status = PMNearestWindowAboveWithQuery(
            99, &actualID, copyTestWindowList
        );
        return status == PMWindowQueryFailed && actualID == kCGNullWindowID ? 0 : 1;
    }
    case PMBridgeTestSingle: {
        const CGWindowID ids[] = { 42 };
        return runQuery(ids, 1, PMWindowQueryFound, 42);
    }
    case PMBridgeTestMultiple: {
        const CGWindowID ids[] = { 7, 12, 99 };
        return runQuery(ids, 3, PMWindowQueryFound, 99);
    }
    case PMBridgeTestHighID: {
        const CGWindowID ids[] = { UINT32_MAX - 1 };
        return runQuery(ids, 1, PMWindowQueryFound, UINT32_MAX - 1);
    }
    case PMBridgeTestOwnership: {
        const CGWindowID ids[] = { 42 };
        testWindowList = makeRawWindowList(ids, 1);
        CFIndex before = CFGetRetainCount(testWindowList);
        CGWindowID actualID = 0;
        PMWindowQueryStatus status = PMNearestWindowAboveWithQuery(
            99, &actualID, copyTestWindowList
        );
        CFIndex after = CFGetRetainCount(testWindowList);
        CFRelease(testWindowList);
        testWindowList = NULL;
        return status == PMWindowQueryFound && actualID == 42 && before == after ? 0 : 1;
    }
    default:
        return 1;
    }
}
