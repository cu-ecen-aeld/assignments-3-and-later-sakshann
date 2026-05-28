#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-
#CROSS_COMPILE=/home/saksham/toolchains/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-

#WRITERDIR=/home/saksham/Desktop/projects/assignment-1-sakshamx/finder-app
FINDER_APP_DIR=$(realpath $(dirname $0))

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}
    echo "linux ---- CWD: $(pwd)"

    # Configure and build the kernel
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j$(nproc) ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules 
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/

echo "Creating the staging directory for the root filesystem"
echo "Using directory ${OUTDIR}/rootfs"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi
echo "CWD: $(pwd)"
# Create necessary base directories
mkdir -p "${OUTDIR}/rootfs"/{bin,dev,etc,home,lib,lib64,proc,sbin,sys,tmp,usr,var}
mkdir -p "${OUTDIR}/rootfs/usr/"{bin,lib,sbin}
mkdir -p "${OUTDIR}/rootfs/var/log"

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    
    git checkout ${BUSYBOX_VERSION}
    # Configure busybox
    make distclean
    make defconfig  
else
    cd busybox
fi

# Make and install busybox
echo "Installing busybox"
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install CONFIG_PREFIX=${OUTDIR}/rootfs 

cd "${OUTDIR}/rootfs"
echo "RooTFS CWD: $(pwd)"

echo "Library dependencies"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

# Add library dependencies to rootfs
SYSROOT="$(${CROSS_COMPILE}gcc --print-sysroot)"
echo "$SYSROOT"

# Copy the dynamic loader (ld-linux-aarch64.so.1)
cp -a ${SYSROOT}/lib/ld-linux-aarch64.so.1 lib/

# Copy shared libraries
cp -a ${SYSROOT}/lib64/libc.so* lib64/
cp -a ${SYSROOT}/lib64/libm.so* lib64/
cp -a ${SYSROOT}/lib64/libresolv.so* lib64/

# Make device nodes
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 666 dev/console c 5 1

# Clean and build the writer utility
cd "${FINDER_APP_DIR}"
echo "Finder app CWD: $(pwd)"
make clean
make CROSS_COMPILE=${CROSS_COMPILE} all
# Copy the finder related scripts and executables to the /home directory
# on the target rootfs
cp -rL .  ${OUTDIR}/rootfs/home

# Chown the root directory
sudo chown -R root:root ${OUTDIR}/rootfs

# TODO: Create initramfs.cpio.gz
cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
cd ${OUTDIR}
gzip -f initramfs.cpio
