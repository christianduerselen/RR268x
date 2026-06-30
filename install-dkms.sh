#!/bin/sh
#
# Install the rr2680 driver via DKMS.
#
# DKMS hooks into the kernel package install/upgrade, so the module is
# rebuilt automatically and immediately whenever a new kernel is installed
# (unlike the hptdrv-monitor shutdown-rebuild mechanism). The PCI modalias
# lets udev auto-load the driver at boot.
#
set -e

MODNAME=rr2680

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

here=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "${here}/dkms.conf" ]; then
  echo "dkms.conf not found next to this script (${here})." >&2
  exit 1
fi

VERSION=$(sed -n 's/^PACKAGE_VERSION="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "${here}/dkms.conf")
if [ -z "${VERSION}" ]; then
  echo "Could not read PACKAGE_VERSION from dkms.conf." >&2
  exit 1
fi

if ! command -v dkms >/dev/null 2>&1; then
  echo "dkms is not installed. Install it first, e.g.:" >&2
  echo "    apt-get install -y dkms        # Debian/Ubuntu" >&2
  echo "    dnf install -y dkms            # Fedora/RHEL" >&2
  exit 1
fi

SRC="/usr/src/${MODNAME}-${VERSION}"

# Drop any previous registration / source tree for this version.
if dkms status -m "${MODNAME}" -v "${VERSION}" 2>/dev/null | grep -q "${MODNAME}"; then
  echo "Removing previous DKMS instance ${MODNAME}/${VERSION}..."
  dkms remove -m "${MODNAME}" -v "${VERSION}" --all || true
fi
rm -rf "${SRC}"

echo "Copying source to ${SRC}..."
mkdir -p "${SRC}"
# Copy the full source tree (the makefile needs inc/, lib/, osm/ and product/),
# excluding VCS data and build artifacts.
tar -C "${here}" \
    --exclude=.git \
    --exclude=.build \
    --exclude='*/.build' \
    --exclude='*.ko' \
    -cf - . | tar -C "${SRC}" -xf -

echo "Registering with DKMS..."
dkms add -m "${MODNAME}" -v "${VERSION}"
dkms build -m "${MODNAME}" -v "${VERSION}"
dkms install -m "${MODNAME}" -v "${VERSION}" --force

echo "Updating module dependencies and loading the driver..."
depmod -a
modprobe "${MODNAME}" || true

echo
dkms status -m "${MODNAME}" -v "${VERSION}"
echo
echo "Done. The driver will be rebuilt automatically on future kernel updates."
