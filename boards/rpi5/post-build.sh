#!/bin/bash
# Runs after building rootfs, before creating images

set -e

BOARD_DIR="$(dirname "$0")"
TARGET_DIR="$1"

echo "═══════════════════════════════════════════════════════════════"
echo "Post-build script for Raspberry Pi 5"
echo "═══════════════════════════════════════════════════════════════"

# ══════════════════════════════════════════════════════════════════════
# BOOT FILES
# ══════════════════════════════════════════════════════════════════════

# Copy config.txt
cp "${BOARD_DIR}/config.txt" "${TARGET_DIR}/boot/"

# Copy cmdline.txt (local boot version)
cp "${BOARD_DIR}/cmdline.txt" "${TARGET_DIR}/boot/"

# ══════════════════════════════════════════════════════════════════════
# SYSTEM CONFIGURATION
# ══════════════════════════════════════════════════════════════════════

# Enable SSH by default
mkdir -p "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/sshd.service \
    "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/sshd.service"

# Enable Docker
ln -sf /usr/lib/systemd/system/docker.service \
    "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/docker.service"

# Enable containerd
ln -sf /usr/lib/systemd/system/containerd.service \
    "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/containerd.service"

# ══════════════════════════════════════════════════════════════════════
# NETWORK CONFIGURATION
# ══════════════════════════════════════════════════════════════════════

# Create network configuration for systemd-networkd
mkdir -p "${TARGET_DIR}/etc/systemd/network"

cat > "${TARGET_DIR}/etc/systemd/network/10-eth0.network" << 'EOF'
[Match]
Name=eth0

[Network]
DHCP=yes

[DHCP]
UseDNS=yes
UseNTP=yes
UseHostname=yes
EOF

# Enable systemd-networkd
ln -sf /usr/lib/systemd/system/systemd-networkd.service \
    "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"

# Enable systemd-resolved
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
    "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"

# ══════════════════════════════════════════════════════════════════════
# KERNEL MODULES
# ══════════════════════════════════════════════════════════════════════

# Load required modules at boot
mkdir -p "${TARGET_DIR}/etc/modules-load.d"

cat > "${TARGET_DIR}/etc/modules-load.d/docker.conf" << 'EOF'
overlay
br_netfilter
EOF

cat > "${TARGET_DIR}/etc/modules-load.d/kubernetes.conf" << 'EOF'
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

# ══════════════════════════════════════════════════════════════════════
# SYSCTL CONFIGURATION
# ══════════════════════════════════════════════════════════════════════

mkdir -p "${TARGET_DIR}/etc/sysctl.d"

cat > "${TARGET_DIR}/etc/sysctl.d/99-kubernetes.conf" << 'EOF'
# Enable IP forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Bridge netfilter
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Increase inotify limits (for container workloads)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Increase file descriptor limits
fs.file-max = 2097152
EOF

# ══════════════════════════════════════════════════════════════════════
# DISABLE SWAP
# ══════════════════════════════════════════════════════════════════════

# Remove any swap entries from fstab
sed -i '/swap/d' "${TARGET_DIR}/etc/fstab" 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════
# FIRST BOOT SCRIPT
# ══════════════════════════════════════════════════════════════════════

mkdir -p "${TARGET_DIR}/usr/local/bin"

cat > "${TARGET_DIR}/usr/local/bin/first-boot.sh" << 'SCRIPT'
#!/bin/bash
# First boot configuration script

LOG="/var/log/first-boot.log"
exec > >(tee -a "$LOG") 2>&1

echo "════════════════════════════════════════════════════════"
echo "First Boot Configuration"
echo "Date: $(date)"
echo "════════════════════════════════════════════════════════"

# Get system info
PI_SERIAL=$(cat /proc/cpuinfo | grep Serial | awk '{print $3}')
PI_MODEL=$(cat /proc/cpuinfo | grep Model | cut -d: -f2 | xargs)
MAC_ADDR=$(ip link show eth0 2>/dev/null | grep ether | awk '{print $2}')
IP_ADDR=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

echo "Serial: $PI_SERIAL"
echo "Model: $PI_MODEL"
echo "MAC: $MAC_ADDR"
echo "IP: $IP_ADDR"

# Resize root filesystem if needed
if [ -b /dev/mmcblk0p2 ]; then
    echo "Resizing root filesystem..."
    resize2fs /dev/mmcblk0p2 || true
fi

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -A
fi

# Try to get configuration from server
CONFIG_SERVER="${CONFIG_SERVER:-192.168.1.5}"
if curl -sf "http://${CONFIG_SERVER}:8080/config/${PI_SERIAL}/hostname" -o /tmp/hostname 2>/dev/null; then
    HOSTNAME=$(cat /tmp/hostname)
    echo "Setting hostname to: $HOSTNAME"
    hostnamectl set-hostname "$HOSTNAME"
fi

if curl -sf "http://${CONFIG_SERVER}:8080/config/${PI_SERIAL}/authorized_keys" -o /tmp/keys 2>/dev/null; then
    echo "Installing SSH authorized keys..."
    mkdir -p /root/.ssh
    cp /tmp/keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Report ready
curl -sf -X POST "http://${CONFIG_SERVER}:8080/api/node-ready/${PI_SERIAL}" \
    -H "Content-Type: application/json" \
    -d "{\"mac\": \"$MAC_ADDR\", \"ip\": \"$IP_ADDR\", \"model\": \"$PI_MODEL\"}" 2>/dev/null || true

# Disable this service after first run
systemctl disable first-boot.service

echo "════════════════════════════════════════════════════════"
echo "First boot complete!"
echo "════════════════════════════════════════════════════════"
SCRIPT

chmod +x "${TARGET_DIR}/usr/local/bin/first-boot.sh"

# Create systemd service for first boot
cat > "${TARGET_DIR}/etc/systemd/system/first-boot.service" << 'EOF'
[Unit]
Description=First Boot Configuration
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/.first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot.sh
ExecStartPost=/usr/bin/touch /var/lib/.first-boot-done
RemainAfterExit=yes
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Enable first-boot service
ln -sf /etc/systemd/system/first-boot.service \
    "${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/first-boot.service"

# ══════════════════════════════════════════════════════════════════════
# CLEANUP
# ══════════════════════════════════════════════════════════════════════

# Remove documentation to save space
rm -rf "${TARGET_DIR}/usr/share/doc"
rm -rf "${TARGET_DIR}/usr/share/man"
rm -rf "${TARGET_DIR}/usr/share/info"

echo "Post-build script complete!"