#ifndef MOUSSE_HID_BRIDGE_H
#define MOUSSE_HID_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct MousseHIDClient MousseHIDClient;

typedef enum MousseHIDProperty {
    MousseHIDPropertyLinearAcceleration = 1,
    MousseHIDPropertyPointerResolution = 2,
} MousseHIDProperty;

MousseHIDClient *MousseHIDClientCreate(void);
void MousseHIDClientDestroy(MousseHIDClient *client);

size_t MousseHIDClientCopyDeviceIDs(MousseHIDClient *client, uint64_t **deviceIDs);
void MousseHIDDeviceIDsDestroy(uint64_t *deviceIDs);

bool MousseHIDClientReadInt64(MousseHIDClient *client, uint64_t deviceID,
                              MousseHIDProperty property, int64_t *value);
bool MousseHIDClientWriteInt64(MousseHIDClient *client, uint64_t deviceID,
                               MousseHIDProperty property, int64_t value);

#endif
