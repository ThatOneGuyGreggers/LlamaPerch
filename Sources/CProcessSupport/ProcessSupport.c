#include "ProcessSupport.h"
#include <arpa/inet.h>
#include <errno.h>
#include <libproc.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <unistd.h>

int llama_check_port(uint16_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return errno;
    // Match normal server bind behavior so a stopped listener's TIME_WAIT sockets
    // do not prevent restart; an active listener still produces EADDRINUSE.
    int reuse = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) != 0) {
        int error = errno;
        close(fd);
        return error;
    }
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int result = bind(fd, (struct sockaddr *)&address, sizeof(address));
    int saved_error = result == 0 ? 0 : errno;
    close(fd);
    return saved_error;
}

static int matches_listener(const struct socket_info *socket, uint16_t port) {
    if (socket->soi_family != AF_INET || socket->soi_kind != SOCKINFO_TCP) return 0;
    const struct tcp_sockinfo *tcp = &socket->soi_proto.pri_tcp;
    return tcp->tcpsi_state == TSI_S_LISTEN &&
        ntohs((uint16_t)tcp->tcpsi_ini.insi_lport) == port &&
        tcp->tcpsi_ini.insi_laddr.ina_46.i46a_addr4.s_addr == htonl(INADDR_LOOPBACK);
}

int llama_owns_listener(int pid, uint16_t port) {
    // A fixed capacity bounds inspection even if the child opens many files.
    struct proc_fdinfo descriptors[4096];
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, descriptors, sizeof(descriptors));
    if (bytes <= 0 || bytes >= (int)sizeof(descriptors)) return -1;
    int count = bytes / (int)sizeof(struct proc_fdinfo);
    for (int i = 0; i < count; i++) {
        if (descriptors[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
        struct socket_fdinfo info;
        int size = proc_pidfdinfo(pid, descriptors[i].proc_fd,
                                 PROC_PIDFDSOCKETINFO, &info, sizeof(info));
        // The child may close a descriptor during inspection; skip that entry.
        if (size != sizeof(info)) continue;
        if (matches_listener(&info.psi, port)) return 1;
    }
    return 0;
}
