# layers/1-bootstrap/rpi/buildroot/Makefile

BUILDROOT_VERSION := 2025.02.10
BUILDROOT_URL := https://buildroot.org/downloads/buildroot-$(BUILDROOT_VERSION).tar.xz
BUILDROOT_DIR := buildroot-$(BUILDROOT_VERSION)
OUTPUT_DIR := output
DEPLOY_DIR := $(OUTPUT_DIR)/deploy
DEFCONFIG := configs/rpi5_tinkerlab_platform_defconfig

# External tree path
BR2_EXTERNAL := $(CURDIR)

.PHONY: all build menuconfig clean distclean help \
        sdcard netboot setup-pi

# ══════════════════════════════════════════════════════════════════════
# MAIN TARGETS
# ══════════════════════════════════════════════════════════════════════

all: build

# Full build (creates both SD card and netboot outputs)
build: configure
	@echo "Building Raspberry Pi 5 image..."
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL)
	@echo ""
	@echo "Build complete! See $(DEPLOY_DIR)/"

# ══════════════════════════════════════════════════════════════════════
# CONVENIENCE TARGETS
# ══════════════════════════════════════════════════════════════════════

# Write SD card image
sdcard: build
	@echo ""
	@echo "Available devices:"
	@lsblk -d -o NAME,SIZE,MODEL | grep -v loop
	@echo ""
	@read -p "Enter device (e.g., sdb): " DEV; \
	echo "Writing to /dev/$$DEV..."; \
	xzcat $(OUTPUT_DIR)/images/sdcard.img.xz | sudo dd of=/dev/$$DEV bs=4M status=progress conv=fsync

# Setup network boot for a Pi
setup-pi: build
	@if [ -z "$(SERIAL)" ]; then \
		echo "Usage: make setup-pi SERIAL=<pi-serial> [NFS_SERVER=<ip>]"; \
		echo ""; \
		echo "Example: make setup-pi SERIAL=abcd1234 NFS_SERVER=192.168.1.5"; \
		exit 1; \
	fi
	@$(DEPLOY_DIR)/setup-pi-netboot.sh $(SERIAL) $(NFS_SERVER)

# ══════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════

configure: extract
	@cp $(DEFCONFIG) $(BUILDROOT_DIR)/.config
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) olddefconfig

menuconfig: extract
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) menuconfig
	@cp $(BUILDROOT_DIR)/.config $(DEFCONFIG)

linux-menuconfig: configure
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) linux-menuconfig

# ══════════════════════════════════════════════════════════════════════
# DOWNLOAD & EXTRACT
# ══════════════════════════════════════════════════════════════════════

download:
	@if [ ! -f "$(BUILDROOT_DIR).tar.xz" ]; then \
		echo "Downloading Buildroot $(BUILDROOT_VERSION)..."; \
		curl -L -# -o "$(BUILDROOT_DIR).tar.xz" \
			"https://buildroot.org/downloads/buildroot-$(BUILDROOT_VERSION).tar.xz"; \
	fi

extract: download
	@if [ ! -d "$(BUILDROOT_DIR)" ]; then \
		echo "Extracting Buildroot..."; \
		tar xf "$(BUILDROOT_DIR).tar.xz"; \
	fi

# ══════════════════════════════════════════════════════════════════════
# CLEANUP
# ══════════════════════════════════════════════════════════════════════

clean:
	@if [ -d "$(BUILDROOT_DIR)" ]; then \
		$(MAKE) -C $(BUILDROOT_DIR) clean; \
	fi
	rm -rf $(OUTPUT_DIR)

distclean:
	rm -rf $(BUILDROOT_DIR) $(BUILDROOT_DIR).tar.xz $(OUTPUT_DIR)

# ══════════════════════════════════════════════════════════════════════
# HELP
# ══════════════════════════════════════════════════════════════════════

help:
	@echo ""
	@echo "Raspberry Pi 5 Homelab Image Builder"
	@echo "════════════════════════════════════"
	@echo ""
	@echo "BUILD:"
	@echo "  make build              Build complete image (SD + netboot)"
	@echo "  make menuconfig         Configure Buildroot packages"
	@echo "  make linux-menuconfig   Configure kernel options"
	@echo ""
	@echo "DEPLOY:"
	@echo "  make sdcard             Write SD card image (interactive)"
	@echo "  make setup-pi SERIAL=x  Setup network boot for Pi"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make build"
	@echo "  make setup-pi SERIAL=abcd1234"
	@echo "  make setup-pi SERIAL=abcd1234 NFS_SERVER=192.168.1.5"
	@echo ""
	@echo "CLEANUP:"
	@echo "  make clean              Clean build artifacts"
	@echo "  make distclean          Remove everything"
	@echo ""