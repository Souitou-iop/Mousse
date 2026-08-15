#include "MousseHIDBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDDeviceKeys.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <stdlib.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client,
                                               CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDServiceClientRef IOHIDEventSystemClientCopyServiceForRegistryID(
    IOHIDEventSystemClientRef client, uint64_t registryID);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service,
                                                 CFStringRef key);
extern Boolean IOHIDServiceClientSetProperty(IOHIDServiceClientRef service,
                                              CFStringRef key, CFTypeRef property);

struct MousseHIDClient {
    IOHIDEventSystemClientRef client;
};

static CFStringRef propertyKey(MousseHIDProperty property) {
    switch (property) {
    case MousseHIDPropertyLinearAcceleration:
        return CFSTR("HIDUseLinearScalingMouseAcceleration");
    case MousseHIDPropertyPointerResolution:
        return CFSTR("HIDPointerResolution");
    }
    return NULL;
}

MousseHIDClient *MousseHIDClientCreate(void) {
    MousseHIDClient *result = calloc(1, sizeof(MousseHIDClient));
    if (!result) return NULL;
    result->client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!result->client) {
        free(result);
        return NULL;
    }

    int page = kHIDPage_GenericDesktop;
    int usage = kHIDUsage_GD_Mouse;
    CFNumberRef pageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void *keys[] = { CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey) };
    const void *values[] = { pageNumber, usageNumber };
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (matching) {
        IOHIDEventSystemClientSetMatching(result->client, matching);
        CFRelease(matching);
    }
    if (pageNumber) CFRelease(pageNumber);
    if (usageNumber) CFRelease(usageNumber);
    return result;
}

void MousseHIDClientDestroy(MousseHIDClient *client) {
    if (!client) return;
    if (client->client) CFRelease(client->client);
    free(client);
}

size_t MousseHIDClientCopyDeviceIDs(MousseHIDClient *client, uint64_t **deviceIDs) {
    if (!client || !client->client || !deviceIDs) return 0;
    *deviceIDs = NULL;
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client->client);
    if (!services) return 0;
    CFIndex count = CFArrayGetCount(services);
    uint64_t *result = count > 0 ? calloc((size_t)count, sizeof(uint64_t)) : NULL;
    if (count > 0 && !result) {
        CFRelease(services);
        return 0;
    }
    size_t written = 0;
    for (CFIndex index = 0; index < count; index++) {
        IOHIDServiceClientRef service =
            (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        uint64_t registryID = 0;
        CFTypeRef registryValue = service ? IOHIDServiceClientGetRegistryID(service) : NULL;
        if (registryValue && CFGetTypeID(registryValue) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)registryValue, kCFNumberSInt64Type, &registryID);
        }
        if (registryID != 0) result[written++] = registryID;
    }
    CFRelease(services);
    *deviceIDs = result;
    return written;
}

void MousseHIDDeviceIDsDestroy(uint64_t *deviceIDs) {
    free(deviceIDs);
}

static IOHIDServiceClientRef copyService(MousseHIDClient *client, uint64_t deviceID) {
    if (!client || !client->client || deviceID == 0) return NULL;
    return IOHIDEventSystemClientCopyServiceForRegistryID(client->client, deviceID);
}

bool MousseHIDClientReadInt64(MousseHIDClient *client, uint64_t deviceID,
                              MousseHIDProperty property, int64_t *value) {
    CFStringRef key = propertyKey(property);
    if (!key || !value) return false;
    IOHIDServiceClientRef service = copyService(client, deviceID);
    if (!service) return false;
    CFTypeRef rawValue = IOHIDServiceClientCopyProperty(service, key);
    bool success = rawValue && CFGetTypeID(rawValue) == CFNumberGetTypeID()
        && CFNumberGetValue((CFNumberRef)rawValue, kCFNumberSInt64Type, value);
    if (rawValue) CFRelease(rawValue);
    CFRelease(service);
    return success;
}

bool MousseHIDClientWriteInt64(MousseHIDClient *client, uint64_t deviceID,
                               MousseHIDProperty property, int64_t value) {
    CFStringRef key = propertyKey(property);
    if (!key) return false;
    IOHIDServiceClientRef service = copyService(client, deviceID);
    if (!service) return false;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &value);
    bool success = number && IOHIDServiceClientSetProperty(service, key, number);
    if (number) CFRelease(number);
    CFRelease(service);
    return success;
}
