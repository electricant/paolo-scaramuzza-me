+++
title = "Isolated Linux Test Environments with QEMU"
date  = 2017-04-01
+++

## Introduction

I regularly need to test network configurations involving multiple Linux
machines. One option is to run one side of the test on my own PC and the
other on a second device, such as a Raspberry Pi. This has the advantage that
every node physically exists and can be examined directly, but the setup is
cumbersome and slow to iterate on, and there is always the risk of leaving
the laptop's own configuration in a broken state.

The ideal arrangement is a testbed of virtual machines connected to one
another through a shared network segment, each running independently, with
access to the internet for downloading packages and updates. As an added
requirement, the setup must be reproducible and launchable with a single
command from the shell.

This article describes how I built such an environment with QEMU. It was
written in 2017; the parts of the setup that would be done differently
today are addressed in the [Modern notes](#modern-notes) section.

## Installing the guest operating system

Installing a Linux guest in QEMU is straightforward and well documented
online&#8239;[\[1\]][1], so I will not cover it here.

## The startup script

The script below launches a testbed consisting of one server and two clients.
Each machine is attached to both the internet and a private virtual layer 2
switch&#8239;[\[2\]][2]. Note that the script must run with root privileges
for the network setup to take effect.

	#!/bin/bash

	# Amount of RAM given to each VM
	RAM_SIZE_MB=512

	# Additional QEMU options
	QEMU_OPTIONS="-enable-kvm -vga std"

	# Interface names
	TAP_SERVER=tapSrv0
	TAP1=tap1
	TAP2=tap2
	BRIDGE=brVrt0

	# Preliminary network interface setup (requires root privileges)
	sudo ip tuntap add $TAP_SERVER mode tap user `whoami`
	sudo ip link set $TAP_SERVER up

	sudo ip tuntap add $TAP1 mode tap user `whoami`
	sudo ip link set $TAP1 up

	sudo ip tuntap add $TAP2 mode tap user `whoami`
	sudo ip link set $TAP2 up

	sudo ip link add $BRIDGE type bridge
	sudo ip link set $BRIDGE up

	sudo ip link set $TAP_SERVER master $BRIDGE
	sudo ip link set $TAP1 master $BRIDGE
	sudo ip link set $TAP2 master $BRIDGE

	# Start the testbed
	qemu-system-i386 $QEMU_OPTIONS -m $RAM_SIZE_MB \
		-netdev tap,id=vlan0,ifname=$TAP_SERVER \
		-device e1000,netdev=vlan0,mac=52:54:00:00:00:01 \
		-netdev user,id=user0 -device e1000,netdev=user0 -hda server.cow &

	qemu-system-i386 $QEMU_OPTIONS -m $RAM_SIZE_MB \
		-netdev tap,id=vlan0,ifname=$TAP1 \
		-device e1000,netdev=vlan0,mac=52:54:00:00:00:02 \
		-netdev user,id=user0 -device e1000,netdev=user0 -hda client1.cow &

	qemu-system-i386 $QEMU_OPTIONS -m $RAM_SIZE_MB \
		-netdev tap,id=vlan0,ifname=$TAP2 \
		-device e1000,netdev=vlan0,mac=52:54:00:00:00:03 \
		-netdev user,id=user0 -device e1000,netdev=user0 -hda client2.cow &

	# Wait for all background jobs to terminate
	wait

	# Teardown of the interfaces
	sudo ip tuntap del $TAP_SERVER mode tap
	sudo ip tuntap del $TAP1 mode tap
	sudo ip tuntap del $TAP2 mode tap

	sudo ip link del $BRIDGE

Getting the interface setup right, on both the host and the guest side, was
the most difficult part; there is a surprising amount of outdated and
misleading material on this topic on the web.

The key point to understand is that QEMU requires a network device instance
for every netdev declared on the command line. Each netdev is therefore given
an id (<tt>-netdev id=netdev_id,netdev_type</tt>) and a device is then
attached to it with <tt>-device hw_type,netdev=netdev_id</tt>. In the script
this pairing is done twice per machine: once for the <tt>tap</tt> netdev
that connects the guest to the private switch, and once for the <tt>user</tt>
netdev that provides internet access through QEMU's built-in user-mode
networking. The role of each netdev type is described in QEMU's networking
documentation&#8239;[\[3\]][3].

On the host side, the desired topology is achieved by bridging the TAP
interfaces together before the virtual machines are started. The relevant
commands are taken from the KVM networking guide&#8239;[\[4\]][4] and adapted
to this situation.

Each virtual machine is launched as a background job (note the
<tt>&</tt> at the end of each command), so the script issues a <tt>wait</tt>
before tearing the network down: it halts until every job has terminated,
guaranteeing that the interfaces are not removed while a guest is still
using them.

## Modern notes

The setup described above remains valid on current QEMU and Linux
releases, but a few of the choices made in 2017 would be updated today:

- <tt>qemu-system-i386</tt> emulates a 32&#8209;bit x86 machine. Unless a
32&#8209;bit guest is specifically needed, the modern equivalent is
<tt>qemu-system-x86_64</tt>, which matches the architecture of current
distributions.
- The <tt>.cow</tt> suffix identifies images in the legacy QCOW version&nbsp;1
format, which still works but has no block device layering or many of the
performance features of its successor. New images are created in the QCOW2
format (suffix <tt>.qcow2</tt>), for example with
<tt>qemu-img create -f qcow2 server.qcow2 10G</tt>.
- The <tt>user</tt> netdev is QEMU's built&#8209;in user&#8209;mode networking
(SLiRP): it is convenient because it requires no host configuration, but it
is NAT&#8209;only, so the host cannot initiate connections to the guests. For
most testbeds this is acceptable; where inbound reachability is required,
the host&#8209;side bridge can be extended with an uplink and an iptables NAT
rule, or the lighter&#8209;weight <tt>slirp4netns</tt> user&#8209;mode stack can
be used in place of the <tt>user</tt> netdev.

## References

<div class="references">

1. [QEMU - ArchWiki -][1]
2. [LAN switching - Wikipedia -][2]
3. [Documentation/Networking - qemu project -][3]
4. [Networking - KVM -][4]

</div>

[1]: https://wiki.archlinux.org/index.php/QEMU "QEMU - ArchWiki -"
[2]: https://en.wikipedia.org/wiki/LAN_switching "LAN switching - Wikipedia -"
[3]: https://wiki.qemu-project.org/Documentation/Networking "Documentation/Networking - qemu project -"
[4]: https://www.linux-kvm.org/page/Networking "Networking - KVM -"
