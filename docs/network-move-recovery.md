# NixNAS Network-Move Recovery Playbook

Use this when NixNAS is moved to a router with a different LAN subnet and its
static address becomes unreachable. This documents the recovery performed when
NixNAS moved from `192.168.100.0/24` to a MikroTik LAN on `192.168.88.0/24`.

## Known values from this recovery

| Item | Value |
|---|---|
| Old NixNAS address | `192.168.100.9/24` |
| Temporary recovery-client address | `192.168.100.10/24` |
| New NixNAS address | `192.168.88.9/24` |
| New gateway | `192.168.88.1` |
| NixNAS interface | `enp3s0` |
| NixNAS MAC | `6C:1F:F7:A9:5A:0B` |
| MikroTik port | `ether2` |
| Recovery-client interface | Active interface attached to the LAN bridge |

Replace these values with those found during a future move.

## Important safety rule

Do **not** add the old `/24` to the MikroTik LAN bridge when that subnet already
exists on its WAN. In this incident, MikroTik `ether1` was already connected to
upstream `192.168.100.0/24`; adding `192.168.100.1/24` to `bridge` created an
ambiguous WAN/LAN subnet and disrupted routing.

Do not bridge WAN and LAN. Recovery only needs temporary layer-2 access from a
LAN client to the NAS.

## 1. Establish the actual state

Read the repository instead of assuming the NAS uses DHCP:

```sh
git grep -nE 'useDHCP|ipv4.addresses|defaultGateway|lanSubnet'
```

On MikroTik, verify the cable, bridge membership, and learned MAC:

```routeros
/interface ethernet monitor ether2 once
/interface bridge port print detail
/interface bridge host print
/ping 192.168.100.9 interface=bridge arp-ping=yes count=5
```

Expected:

- `ether2` reports `link-ok` and is an active member of `bridge`.
- The bridge learns `6C:1F:F7:A9:5A:0B` on `ether2`.
- ARP ping receives replies from that MAC.

Link LEDs or a learned MAC prove only layer 2. If ARP ping fails, check that the
cable is in the NixOS-configured physical NIC; this NAS has two NICs but only
`enp3s0` is configured.

## 2. Recover SSH from any client on the same bridge

The recovery client may use Ethernet or wireless, but it must be on the same
untagged LAN bridge as NixNAS and must not be subject to client isolation.
Using that client's native network tools:

1. Add a temporary secondary address in the NAS's old subnet.
2. Add an on-link `/32` route for the old NAS address through the LAN interface.
3. Add a static neighbor entry mapping the old NAS address to its real MAC.
4. Verify the route and neighbor before trying SSH.

A static neighbor avoids route conflicts with VPN software such as Tailscale and
also avoids relying on broadcast ARP during recovery.

### Linux client

```sh
IFACE="replace-with-lan-interface"
sudo ip addr add 192.168.100.10/24 dev "$IFACE"
sudo ip route replace 192.168.100.9/32 dev "$IFACE"
sudo ip neigh replace 192.168.100.9 lladdr 6c:1f:f7:a9:5a:0b nud permanent dev "$IFACE"
ip route get 192.168.100.9
ip neigh show 192.168.100.9
```

### BSD client

```sh
IFACE="replace-with-lan-interface"
sudo ifconfig "$IFACE" alias 192.168.100.10 netmask 255.255.255.0 broadcast 192.168.100.255
sudo route -n delete -host 192.168.100.9 2>/dev/null || true
sudo route -n add -host 192.168.100.9 -interface "$IFACE"
sudo arp -s 192.168.100.9 6c:1f:f7:a9:5a:0b
route -n get 192.168.100.9
arp -an | grep 192.168.100.9
```

Then connect from that client:

```sh
ping 192.168.100.9
ssh admin@192.168.100.9
```

If MikroTik ARP ping succeeds but the client still cannot connect, inspect ARP
on the NAS port while retrying the client ping:

```routeros
/tool/sniffer/quick filter-interface=ether2 filter-mac-protocol=arp
```

## 3. Update the repository

Change every tracked runtime reference, not just the interface address:

- `configuration.nix`: interface address, default gateway, Fail2Ban LAN.
- `modules/settings.nix`: Tailscale-advertised `lanSubnet`.
- `modules/media/downloaders.nix`: SABnzbd host whitelist.
- Network documentation.

Find stale values with:

```sh
git grep -n '192\.168\.100'
```

For this move they became:

```nix
address = "192.168.88.9";
defaultGateway = "192.168.88.1";
```

and all LAN subnet references became `192.168.88.0/24`. Confirm the static NAS
address is outside the MikroTik DHCP pool:

```routeros
/ip pool print detail
```

The default `192.168.88.10-192.168.88.254` pool does not include `.9`.

Validate, commit, and push from the development machine:

```sh
scripts/validate
git diff --check
git add configuration.nix modules/settings.nix modules/media/downloaders.nix docs/ README.md
git commit -m "Update NixNAS for new LAN"
git push
```

## 4. Transfer the commit when the NAS has no internet

A NAS still using its old gateway cannot resolve or reach GitHub. Create an
offline Git bundle on the development client:

```sh
git bundle create /tmp/nixnas-network.bundle main
git bundle verify /tmp/nixnas-network.bundle
scp /tmp/nixnas-network.bundle admin@192.168.100.9:/tmp/
```

In the NAS SSH session:

```sh
cd /etc/nixos
sudo git fetch /tmp/nixnas-network.bundle main
sudo git merge --ff-only FETCH_HEAD
```

Do not copy the whole working tree or overwrite secrets.

## 5. Restore internet temporarily and build

Before rebuilding, add the new address to the running system while retaining
the old address used by the current SSH session:

```sh
sudo ip addr add 192.168.88.9/24 dev enp3s0
sudo ip route replace default via 192.168.88.1 dev enp3s0
ping -c 2 1.1.1.1
getent hosts cache.nixos.org
```

Build the new generation without switching the live network underneath SSH:

```sh
cd /etc/nixos
sudo nixos-rebuild boot --flake .#nixnas
sudo reboot
```

Do **not** use `--option substituters ""` as an offline workaround. It disables
the binary cache and may try to build the entire dependency graph while still
needing unavailable upstream source tarballs.

The temporary `ip addr` and `ip route` commands affect only the running kernel.
Reboot clears them; the rebuilt NixOS configuration then installs the new
address and gateway persistently.

## 6. Verify after reboot

From a normal LAN client:

```sh
ssh admin@192.168.88.9
```

On NixNAS:

```sh
ip -4 addr show dev enp3s0
ip route
```

Expected routes include:

```text
192.168.88.0/24 dev enp3s0 ... src 192.168.88.9
default via 192.168.88.1 dev enp3s0
```

## 7. Finish external configuration

Update the unproxied Cloudflare wildcard A record:

```text
*.8004228.xyz -> 192.168.88.9
```

An already-authenticated Tailscale node does not reapply changed
`extraUpFlags`. Explicitly advertise the new route:

```sh
sudo tailscale set --advertise-routes=192.168.88.0/24
sudo tailscale debug prefs | grep -A2 AdvertiseRoutes
```

Then approve the new route in the Tailscale admin console. If auto-approval is
configured, it may already be enabled rather than shown as pending.

## 8. Clean up the recovery client

After confirming the new address works, remove the static neighbor, host route,
and temporary secondary address using the same client's native tools.

### Linux client

```sh
IFACE="replace-with-lan-interface"
sudo ip neigh del 192.168.100.9 dev "$IFACE" 2>/dev/null || true
sudo ip route del 192.168.100.9/32 dev "$IFACE" 2>/dev/null || true
sudo ip addr del 192.168.100.10/24 dev "$IFACE"
```

### BSD client

```sh
IFACE="replace-with-lan-interface"
sudo arp -d 192.168.100.9 2>/dev/null || true
sudo route -n delete -host 192.168.100.9 2>/dev/null || true
sudo ifconfig "$IFACE" -alias 192.168.100.10
```

Also remove any temporary MikroTik bridge address left from earlier attempts:

```routeros
/ip address print
```

Only remove an address positively identified as the temporary recovery entry;
do not remove the normal `192.168.88.1/24` bridge address.
