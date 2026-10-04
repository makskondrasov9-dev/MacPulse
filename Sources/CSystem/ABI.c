#include "CSystem.h"
_Static_assert(sizeof(MonitorSMCMessage) == 80, "Unexpected AppleSMC message size");
_Static_assert(offsetof(MonitorSMCMessage, keyInfo) == 28, "Unexpected key info offset");
_Static_assert(offsetof(MonitorSMCMessage, command) == 42, "Unexpected command offset");
_Static_assert(offsetof(MonitorSMCMessage, bytes) == 48, "Unexpected payload offset");
