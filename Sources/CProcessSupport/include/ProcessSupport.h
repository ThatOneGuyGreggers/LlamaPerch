#ifndef LLAMA_PROCESS_SUPPORT_H
#define LLAMA_PROCESS_SUPPORT_H
#include <stdint.h>
// Returns 1 if this PID owns a listening IPv4 loopback socket, 0 if not,
// or -1 if ownership could not be checked. Inspects at most 4096 descriptors.
int llama_owns_listener(int pid, uint16_t port);
// Returns 0 if the loopback port can be bound, otherwise an errno value.
int llama_check_port(uint16_t port);
#endif
