// AppleSMC read protocol, documented by the MIT-licensed Stats project.
// See THIRD_PARTY_NOTICES.md. No write commands or fan-control operations.
#include "CStats.h"
#include <IOKit/IOKitLib.h>
#include <stddef.h>
#include <string.h>

typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } version;
    struct { uint16_t version, length; uint32_t cpu, gpu, memory; } limits;
    struct { uint32_t size, type; uint8_t attributes; } info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCPacket;
_Static_assert(sizeof(SMCPacket) == 80 && offsetof(SMCPacket, bytes) == 48, "SMC ABI");

static uint32_t code(const char *key) {
    return (uint32_t)(uint8_t)key[0] << 24 | (uint32_t)(uint8_t)key[1] << 16 |
           (uint32_t)(uint8_t)key[2] << 8 | (uint8_t)key[3];
}
static void text_code(uint32_t value, char text[5]) {
    for (int i = 0; i < 4; i++) text[i] = (char)(value >> (24 - 8 * i));
    text[4] = 0;
}
static int call(uint32_t connection, SMCPacket *input, SMCPacket *output) {
    size_t size = sizeof(*output);
    memset(output, 0, size);
    return IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size) == KERN_SUCCESS &&
           size == sizeof(*output) && output->result == 0;
}
uint32_t zs_smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? connection : 0;
}
void zs_smc_close(uint32_t connection) { if (connection) IOServiceClose(connection); }
int zs_smc_key(uint32_t connection, uint32_t index, char key[5]) {
    SMCPacket input = {0}, output;
    input.command = 8; input.index = index;
    if (!call(connection, &input, &output)) return 0;
    text_code(output.key, key); return 1;
}
int zs_smc_read(uint32_t connection, const char *key, char type[5], uint8_t bytes[32]) {
    if (!key || strlen(key) != 4) return 0;
    SMCPacket input = {0}, output;
    input.key = code(key); input.command = 9;
    if (!call(connection, &input, &output) || output.info.size == 0 || output.info.size > 32) return 0;
    input.info.size = output.info.size;
    text_code(output.info.type, type);
    input.command = 5;
    if (!call(connection, &input, &output)) return 0;
    memcpy(bytes, output.bytes, input.info.size);
    return (int)input.info.size;
}
