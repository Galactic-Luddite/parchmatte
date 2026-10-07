#ifndef WINDOW_LIST_BRIDGE_TEST_SUPPORT_H
#define WINDOW_LIST_BRIDGE_TEST_SUPPORT_H

#include <stdint.h>

typedef uint32_t PMBridgeTestCase;
enum {
    PMBridgeTestEmpty,
    PMBridgeTestFailure,
    PMBridgeTestSingle,
    PMBridgeTestMultiple,
    PMBridgeTestHighID,
    PMBridgeTestOwnership,
};

int PMRunWindowListBridgeTest(PMBridgeTestCase testCase);

#endif
