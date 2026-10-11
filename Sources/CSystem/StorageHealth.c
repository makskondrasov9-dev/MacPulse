#include "CSystem.h"
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/ata/ATASMARTLib.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <string.h>

// Read-only: no SMART enable/autosave commands and no disk self-tests.
int MonitorReadSMART(uint32_t service, int nvme, uint8_t *data, int *condition) {
    *condition = -1;
    memset(data, 0, 512);
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn error = IOCreatePlugInInterfaceForService(service,
        nvme ? kIONVMeSMARTUserClientTypeID : kIOATASMARTUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    if (error != kIOReturnSuccess) return error;
    if (!plugin) return kIOReturnUnsupported;
    if (nvme) {
        IONVMeSMARTInterface **smart = NULL;
        HRESULT query = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
        IODestroyPlugInInterface(plugin);
        if (query != S_OK || !smart) return kIOReturnUnsupported;
        NVMeSMARTData reading = {0};
        error = (*smart)->SMARTReadData(smart, &reading);
        if (error == kIOReturnSuccess) {
            memcpy(data, &reading, 512);
            *condition = reading.CRITICAL_WARNING == 0 ? 0 : 1;
        }
        (*smart)->Release(smart);
    } else {
        IOATASMARTInterface **smart = NULL;
        HRESULT query = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOATASMARTInterfaceID), (LPVOID *)&smart);
        IODestroyPlugInInterface(plugin);
        if (query != S_OK || !smart) return kIOReturnUnsupported;
        Boolean exceeded = false;
        if ((*smart)->SMARTReturnStatus(smart, &exceeded) == kIOReturnSuccess) *condition = exceeded ? 1 : 0;
        ATASMARTData reading = {0};
        error = (*smart)->SMARTReadData(smart, &reading);
        if (error == kIOReturnSuccess && (*smart)->SMARTValidateReadData(smart, &reading) == kIOReturnSuccess) {
            memcpy(data, &reading, 512);
        } else { error = kIOReturnUnsupported; }
        (*smart)->Release(smart);
    }
    return error;
}
_Static_assert(sizeof(NVMeSMARTData) == 512, "Unexpected NVMe SMART layout");
_Static_assert(sizeof(ATASMARTData) == 512, "Unexpected ATA SMART layout");
