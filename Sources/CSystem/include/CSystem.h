#ifndef IMAC_MONITOR_SYSTEM_H
#define IMAC_MONITOR_SYSTEM_H
#include <stdint.h>
#include <stddef.h>
#include <libproc.h>
#include <mach/mach.h>

// The process task port is constant after startup. Keep the Darwin macro in C
// so Swift 6 does not expose mach_task_self_ as mutable shared Swift state.
static inline mach_port_t MonitorTaskSelf(void) { return mach_task_self(); }

// AppleSMC user-client ABI. Natural C alignment is required; do not pack.
typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} MonitorSMCVersion;
typedef struct {
    uint16_t version, length;
    uint32_t cpu, gpu, memory;
} MonitorSMCLimits;
typedef struct {
    uint32_t dataSize, dataType;
    uint8_t attributes;
} MonitorSMCKeyInfo;
typedef struct {
    uint32_t key;
    MonitorSMCVersion version;
    MonitorSMCLimits limits;
    MonitorSMCKeyInfo keyInfo;
    uint8_t result, status, command;
    uint32_t data32;
    uint8_t bytes[32];
} MonitorSMCMessage;
// Caller owns *result and releases it with free(). A nonzero return is errno.
typedef struct {
    char name[16]; // IF_NAMESIZE on Darwin
    uint32_t index;
    uint64_t received, sent;
} MonitorNetworkCounter;
int MonitorCopyNetworkCounters(MonitorNetworkCounter **result, size_t *count);
#endif
