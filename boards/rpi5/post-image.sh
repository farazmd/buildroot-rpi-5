#!/bin/bash
# Runs after rootfs is created, generates final images

set -e

BOARD_DIR="$(dirname "$0")"
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# ══════════════════════════════════════════════════════════════════════
# PREPARE BOOT PARTITION FILES
# ══════════════════════════════════════════════════════════════════════

BOOT_DIR="${BINARIES_DIR}/rpi-firmware"
mkdir -p "${BOOT_DIR}/overlays"

# Copy firmware files
cp "${BINARIES_DIR}/"*.dtb "${BOOT_DIR}/" 2>/dev/null || true
cp "${BINARIES_DIR}/rpi-firmware/"* "${BOOT_DIR}/" 2>/dev/null || true
cp -r "${BINARIES_DIR}/rpi-firmware/overlays/"* "${BOOT_DIR}/overlays/" 2>/dev/null || true

# Copy kernel
cp "${BINARIES_DIR}/Image" "${BOOT_DIR}/"

# Copy boot config
cp "${BOARD_DIR}/config.txt" "${BOOT_DIR}/"
cp "${BOARD_DIR}/cmdline.txt" "${BOOT_DIR}/"
cp "${BOARD_DIR}/cmdline-netboot.txt.tmpl" "${BOOT_DIR}/"

# ══════════════════════════════════════════════════════════════════════
# GENERATE SD CARD IMAGE
# ══════════════════════════════════════════════════════════════════════

rm -rf "${GENIMAGE_TMP}"

genimage \
    --rootpath "${TARGET_DIR}" \
    --tmppath "${GENIMAGE_TMP}" \
    --inputpath "${BINARIES_DIR}" \
    --outputpath "${BINARIES_DIR}" \
    --config "${GENIMAGE_CFG}"

# ══════════════════════════════════════════════════════════════════════
# CREATE ADDITIONAL OUTPUTS
# ══════════════════════════════════════════════════════════════════════

# Compress SD card image
echo "Compressing SD card image..."
xz -9 -k -f "${BINARIES_DIR}/sdcard.img"

# Create output directory structure for deployment
OUTPUT_DIR="${BINARIES_DIR}/deploy"
mkdir -p "${OUTPUT_DIR}"

# Copy files for network boot deployment
cp "${BINARIES_DIR}/sdcard.img.xz" "${OUTPUT_DIR}/"
cp "${BINARIES_DIR}/rootfs.tar.gz" "${OUTPUT_DIR}/"
cp "${BINARIES_DIR}/Image" "${OUTPUT_DIR}/kernel8.img"
cp -r "${BOOT_DIR}" "${OUTPUT_DIR}/boot"


echo ""
echo "📦 Creating setup script..."

cat > "${DEPLOY_DIR}/setup-pi-netboot.sh" << 'SCRIPT'
#!/bin/bash
# Auto-generated setup script for Raspberry Pi network boot
set -e

PI_SERIAL="$1"
NFS_SERVER="${2:-$(hostname -I | awk '{print $1}')}"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp}"
NFS_ROOT="${NFS_ROOT:-/srv/nfs/rpi}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NETBOOT_DIR="${SCRIPT_DIR}/netboot"

if [ -z "$PI_SERIAL" ]; then
    echo "Usage: $0 <pi-serial> [nfs-server-ip]"
    echo ""
    echo "Example: $0 abcd1234 192.168.1.5"
    exit 1
fi

echo "Setting up network boot for Pi: ${PI_SERIAL}"
echo "NFS Server: ${NFS_SERVER}"

# Create TFTP directory
PI_TFTP="${TFTP_ROOT}/${PI_SERIAL}"
mkdir -p "${PI_TFTP}"

# Copy boot files
cp -r ${NETBOOT_DIR}/boot/* "${PI_TFTP}/"

# Generate cmdline.txt with actual values
sed "s/__SERIAL__/${PI_SERIAL}/g; s/__NFS_SERVER__/${NFS_SERVER}/g" \
    "${NETBOOT_DIR}/boot/cmdline-netboot.txt.tmpl" > "${PI_TFTP}/cmdline.txt"

# Create NFS directory
PI_NFS="${NFS_ROOT}/${PI_SERIAL}"
mkdir -p "${PI_NFS}"

# Extract rootfs
echo "Extracting rootfs (this may take a moment)..."
tar xzf "${NETBOOT_DIR}/rootfs/rootfs.tar.gz" -C "${PI_NFS}"

# Update NFS exports
if ! grep -q "${PI_NFS}" /etc/exports 2>/dev/null; then
    echo "${PI_NFS} *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -ra
fi

echo ""
echo "Setup complete!"
echo "   TFTP: ${PI_TFTP}"
echo "   NFS:  ${PI_NFS}"
echo ""
echo "Power on the Pi to network boot."
SCRIPT

chmod +x "${DEPLOY_DIR}/setup-pi-netboot.sh"

echo "═══════════════════════════════════════════════════════════════"
echo "Build complete! Output files:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "SD Card Image:    ${OUTPUT_DIR}/sdcard.img.xz"
echo "Root FS Tarball:  ${OUTPUT_DIR}/rootfs.tar.gz"
echo "Kernel:           ${OUTPUT_DIR}/kernel8.img"
echo "Boot Files:       ${OUTPUT_DIR}/boot/"
echo ""
echo "To write SD card: xzcat sdcard.img.xz | sudo dd of=/dev/sdX bs=4M"
echo ""
echo "  Network Boot Package:"
echo "     ${DEPLOY_DIR}/netboot/"
echo "     Setup with: ./setup-pi-netboot.sh <serial> [nfs-server]"
echo ""
echo "════════════════════════════════════════════════════════════════"