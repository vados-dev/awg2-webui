# MikroTik CHR Deployment Guide

AmneziaWG 2.0 Web UI on MikroTik RouterOS Container (CHR/amd64).

## Requirements

- RouterOS 7.6+ with Container support
- CHR or physical device with amd64 architecture
- External disk mounted (e.g. `disk1`)
- veth interface configured

## Critical CHR-Specific Notes

### 1. iptables-legacy (REQUIRED)
RouterOS containers use an older kernel that requires `iptables-legacy`.
The image is already built with this — do **not** replace with `iptables`.

PostUp rule uses:
```
iptables-legacy -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
```

### 2. nginx sendfile/aio (REQUIRED)
RouterOS uses overlayfs which does not support `sendfile` or `aio`.
The image has `sendfile off; aio off;` in nginx.conf — do **not** change.

### 3. No bind mount for AWG config
Do **not** bind-mount `/etc/amnezia/amneziawg` — overlayfs whiteout files
cause PermissionError on write. Use a named volume or leave it inside the container.

### 4. SSTP loop prevention
If MikroTik uses SSTP to connect to CHR, add a static route to prevent loop:
```
/ip route add dst-address=<CHR_IP>/32 gateway=<ISP_GW>
```

---

## Step-by-Step Deployment

### Step 1 — Pull image on a Linux machine

```bash
docker pull ghcr.io/sysmslog/awg2-webui:latest
docker save ghcr.io/sysmslog/awg2-webui:latest -o awg2-webui.tar
```

### Step 2 — Upload to CHR

```bash
scp -P 2222 awg2-webui.tar admin@<CHR_IP>:disk1/awg2-webui.tar
```

### Step 3 — Configure RouterOS

```routeros
# 1. Create veth interface
/interface veth add name=veth-awg address=10.10.5.2/24 gateway=10.10.5.1

# 2. Create bridge and add veth
/interface bridge add name=br-awg
/interface bridge port add bridge=br-awg interface=veth-awg

# 3. Assign IP to bridge
/ip address add address=10.10.5.1/24 interface=br-awg

# 4. NAT: masquerade container traffic
/ip firewall nat add chain=srcnat src-address=10.10.5.0/24 action=masquerade

# 5. Port forward: UDP 443 → container (AmneziaWG QUIC mimicry)
/ip firewall nat add chain=dstnat protocol=udp dst-port=443 \
    action=dst-nat to-addresses=10.10.5.2 to-ports=51820 in-interface=ether1

# 6. Port forward: HTTPS 9443 → container Web UI
/ip firewall nat add chain=dstnat protocol=tcp dst-port=9443 \
    action=dst-nat to-addresses=10.10.5.2 to-ports=443 in-interface=ether1
```

### Step 4 — Create environment list

```routeros
/container envs add name=awgui-env key=WEB_USER value=admin
/container envs add name=awgui-env key=WEB_PASS value=YourStrongPassword
/container envs add name=awgui-env key=SECRET_KEY value=your-random-secret-32chars
/container envs add name=awgui-env key=AWG_ENDPOINT value=<CHR_PUBLIC_IP>:443
```

### Step 5 — Load and start container

```routeros
/container add file=disk1/awg2-webui.tar \
    interface=veth-awg \
    root-dir=disk1/docker/awg2-webui \
    envlist=awgui-env \
    start-on-boot=yes \
    logging=yes

/container start 0
```

### Step 6 — Verify

```routeros
/container print
# Should show: status=running

/log print where topics~"container"
# Should show: AWG started, nginx running
```

---

## Accessing the Web UI

```
https://<CHR_PUBLIC_IP>:9443
```

Default credentials: `admin` / value of `WEB_PASS` env var.

On first visit, browser will warn about self-signed certificate — accept it,
or configure a real certificate via **Settings → SSL → Let's Encrypt**.

---

## Updating

```bash
# Pull new image
docker pull ghcr.io/sysmslog/awg2-webui:latest
docker save ghcr.io/sysmslog/awg2-webui:latest -o awg2-webui-new.tar
scp -P 2222 awg2-webui-new.tar admin@<CHR_IP>:disk1/awg2-webui-new.tar
```

```routeros
/container stop 0
/container remove 0
/container add file=disk1/awg2-webui-new.tar \
    interface=veth-awg \
    root-dir=disk1/docker/awg2-webui \
    envlist=awgui-env \
    start-on-boot=yes
/container start 0
```

> **Note:** Peer configs are stored inside the container's root-dir.
> Back up `/etc/amnezia/amneziawg/` before updating.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Container won't start | Check `/log print where topics~"container"` |
| AWG not starting | Run `awg show awg0` inside container — check if amneziawg-go is running |
| No handshake | Verify UDP 443 NAT rule and client H1-H4 match server |
| Web UI unreachable | Check port 9443 NAT rule; verify veth has correct IP |
| PermissionError on save | Expected on first write — built-in retry handles it automatically |
