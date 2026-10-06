#include "CSystem.h"
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/route.h>
#include <net/if_media.h>
#include <sys/ioctl.h>
#include <sys/sockio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

// Unlike getifaddrs/if_data, NET_RT_IFLIST2 exposes 64-bit byte counters.
int MonitorCopyNetworkCounters(MonitorNetworkCounter **result, size_t *count) {
    *result = NULL;
    *count = 0;
    int mib[] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0 };
    for (int attempt = 0; attempt < 3; attempt++) {
        size_t length = 0;
        if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0) return errno;
        if (length == 0) return 0;
        char *buffer = malloc(length);
        if (!buffer) return ENOMEM;
        if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) {
            int error = errno;
            free(buffer);
            if (error == ENOMEM) continue; // Interface list changed between calls.
            return error;
        }
        size_t capacity = length / sizeof(struct if_msghdr2) + 1;
        MonitorNetworkCounter *rows = calloc(capacity, sizeof(*rows));
        if (!rows) { free(buffer); return ENOMEM; }
        int mediaSocket = socket(AF_INET, SOCK_DGRAM, 0);
        for (size_t offset = 0; offset < length;) {
            // All routing messages begin with length, version and type.
            unsigned short messageLength;
            if (length - offset < 4) goto malformed;
            memcpy(&messageLength, buffer + offset, sizeof(messageLength));
            if (messageLength < 4 || messageLength > length - offset) goto malformed;
            if ((unsigned char)buffer[offset + 3] == RTM_IFINFO2) {
                if (messageLength < sizeof(struct if_msghdr2)) goto malformed;
                struct if_msghdr2 message;
                memcpy(&message, buffer + offset, sizeof(message));
                if ((message.ifm_flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
                    && !(message.ifm_flags & IFF_LOOPBACK)) {
                    MonitorNetworkCounter *row = &rows[*count];
                    if (if_indextoname(message.ifm_index, row->name)) {
                        struct ifmediareq media = {0};
                        strlcpy(media.ifm_name, row->name, sizeof(media.ifm_name));
                        if (mediaSocket >= 0 && ioctl(mediaSocket, SIOCGIFMEDIA, &media) == 0
                            && (media.ifm_status & IFM_AVALID) && !(media.ifm_status & IFM_ACTIVE)) {
                            offset += messageLength;
                            continue;
                        }
                        row->index = message.ifm_index;
                        row->received = message.ifm_data.ifi_ibytes;
                        row->sent = message.ifm_data.ifi_obytes;
                        (*count)++;
                    }
                }
            }
            offset += messageLength;
        }
        if (mediaSocket >= 0) close(mediaSocket);
        free(buffer);
        *result = rows;
        return 0;
malformed:
        if (mediaSocket >= 0) close(mediaSocket);
        free(rows);
        free(buffer);
        *count = 0;
        return EINVAL;
    }
    return ENOMEM;
}
