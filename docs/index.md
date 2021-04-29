# vpsAdminOS

Lightweight host for Linux system containers.

---

vpsAdminOS is an operating system that serves as a host for container
virtualization. It is based on [not-os](https://github.com/cleverca22/not-os/)
and NixOS.

vpsAdminOS was designed for purposes of [vpsFree.cz](https://vpsfree.org),
a non-profit association that provides virtual servers to its members. We were
using OpenVZ Legacy since 2009, but needed to upgrade to a newer kernel,
as modern Linux distributions stopped supporting the OpenVZ Legacy kernel.
We didn't like the new OpenVZ 7 and seemed to have different needs than what
LXC/LXD provided, so we decided to create our custom toolset to manage
the containers to bring us closer to the experience of OpenVZ on upstream
kernels. vpsAdminOS is built on:

- [Upstream kernel with a mix of out-of-tree patches](https://github.com/vpsfreecz/linux)
- AppArmor
- LXC, LXCFS
- runit
- BIRD
- ZFS
- osctl/osctld (userspace tools bundled with vpsAdminOS)

vpsAdminOS provides means to create and manage system containers, which look
and feel as much as a virtual machine as possible. It focuses on user
namespace and cgroup management to isolate containers, all containers are
running as unprivileged. One can set resource limits on a single container
or groups of containers, allowing for fine-grained control and resource sharing.

*osctl*/*osctld* is an abstraction on top of LXC, managing system users, LXC
homes, cgroups and system containers. vpsAdminOS uses ZFS to store containers
and configuration. We have patched ZFS for seamless integration with user
namespaces, i.e. user/group id mapping on the file system level, until a proper
solution is provided in upstream to avoid chowning all containers' files into
appropriate user namespaces.

## Links

* IRC: #vpsadminos @ irc.freenode.net
* Git: <https://github.com/vpsfreecz/vpsadminos>
* Man pages: <https://man.vpsadminos.org/>
* OS and program references: <https://ref.vpsadminos.org/>
* ISO images: <https://iso.vpsadminos.org/>
