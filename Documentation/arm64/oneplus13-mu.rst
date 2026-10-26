OnePlus 13: Linux payload for Mu-Silicium
=======================================

This is experimental bring-up infrastructure, not an installable Debian image
or a hardware-tested boot recipe. It builds this repository's kernel without
rebasing it. No phone partitions are written by the workflow.

Boot chain
----------

Android bootloader -> Mu-Silicium for dodge -> ARM64 EFI bootloader or EFI stub
-> this kernel + initramfs -> Debian/Arch ARM64 rootfs -> desktop.

Mu is UEFI firmware. It initializes the platform and supplies EFI services,
a memory map, a display framebuffer and (on the dodge port) a device tree.
It does not contain Debian, Plasma, this Linux kernel or a Linux initramfs.
Its internal-storage boot path can launch an ARM64 EFI application from a
readable FAT ESP, conventionally EFI/BOOT/BOOTAA64.EFI. rEFInd or GRUB may be
used there; linux.efi is also directly executable using the Linux EFI stub.
An unsigned payload needs a Mu configuration that permits unsigned EFI images.

For dodge, Mu's status page lists Linux boot, internal storage and USB device
mode as supported, but USB host mode as unsupported. Do not assume that an
ordinary USB installer stick can boot on this device.

Build and artifacts
-------------------

Actions -> OnePlus 13 - Mu Linux payload -> Run workflow (branch v6.16).
Pushes and pull requests to v6.16 also run it. If GitHub disabled Actions on
this new fork, enable workflows in the Actions tab first, then run manually.

Each run builds two profiles:

* firmware: disables DRM_MSM so simpledrm can retain the firmware framebuffer.
  Start with this profile when using Mu. It does not provide GPU acceleration.
* native: enables the existing MSM DPU/DSI and OnePlus panel drivers, with
  simpledrm also available for early output. Display takeover is experimental.

Both retain the existing sm8750.config, then apply dodge-mu.config. ADSP,
CDSP and modem automatic loading through QCOM_Q6V5_PAS is disabled for this
initial boot test. Firmware blobs are not bundled. This is not an assertion
that these subsystems are supported. The board DTS itself is unchanged.

Artifacts include uncompressed Image and its identical linux.efi copy,
Image.gz (not the direct EFI-shell payload), sm8750-oneplus-dodge.dtb,
modules.tar.gz, kernel.config, System.map, kernelrelease.txt, build metadata
and SHA256SUMS. Logs and final Kconfig are uploaded even on build failure.

The modules archive must be installed into the rootfs used for that exact
kernel release. Do not mix firmware/native modules or modules from other runs.
The build verifies required options after olddefconfig and checks ARM64 PE/COFF
and DTB headers; successful compilation does not establish hardware support.

Local build on Ubuntu 24.04, with the same dependencies as the workflow::

    DISPLAY_PROFILE=firmware bash scripts/build-dodge-mu.sh

Use a clean output directory when changing profile. The default toolchain is
LLVM 18. The script supports JOBS and DISPLAY_PROFILE environment variables.

Preparing a Debian ARM64 installation
------------------------------------

Use a Debian arm64 rootfs, not an amd64 PC installer ISO. Install the matching
modules, kernel config and kernel into it, install initramfs-tools, then build
an initramfs for the exact release in kernelrelease.txt inside an ARM64 chroot
or an ARM64 machine. An x86 host requires correctly configured user emulation
for such a chroot. Run depmod for that release before generating the initramfs.
Debian's stock kernel package is not a replacement for the dodge kernel.

For example, after installing the payload into that Debian rootfs and making
/boot/config-<release> and /boot/vmlinuz-<release> available, the guest commands
are ``depmod <release>`` and ``update-initramfs -c -k <release>``. Replace the
placeholder with the exact release, not the host's ``uname -r``. Kernel, DTB,
initramfs and rootfs must all belong to the intended boot configuration.

The ESP needs the EFI bootloader, linux.efi and that generated initramfs.
The ext4 rootfs needs Debian userspace, matching modules, a configured user,
and a desktop such as kde-plasma-desktop. USB NCM is built in, but IP addresses,
SSH and Internet sharing must be configured in userspace and on the host.

Example rEFInd manual stanza (replace ROOTFS_UUID with the Linux rootfs UUID,
and put the files at these paths on the ESP)::

    menuentry "Debian ARM64 - OnePlus 13" {
        loader /linux.efi
        initrd /initramfs.img
        options "root=UUID=ROOTFS_UUID rootwait rw console=tty0 loglevel=7"
    }

Example EFI-shell invocation, if the ESP is mapped as fs0::

    fs0:
    \linux.efi initrd=\initramfs.img root=UUID=ROOTFS_UUID rootwait rw console=tty0 loglevel=7

Start with the DTB provided by a matching Mu dodge build. The separately built
DTB is included for development and deliberate replacement. If a DTB override
is necessary, EFI stub accepts ``dtb=\sm8750-oneplus-dodge.dtb``, but it can
discard runtime data added by firmware. Do not add acpi=force for this DT-based
SM8750 port merely because an older generic guide recommends it.

Plasma requires working DRM output, input and compatible Mesa software
rendering in userspace. Neither profile adds Adreno 830 support. A working
framebuffer does not by itself guarantee a working Plasma session or smooth
performance. Test the console and USB networking before enabling the desktop.

RAM-only operation
------------------

An ordinary Debian initramfs mounts its rootfs from a block device. RAM-only
operation needs an initramfs containing the full userspace, or a custom init
that copies the rootfs to tmpfs and switches into it. This workflow builds
neither. Files can live on UFS while the running rootfs is in RAM; that differs
from having no UFS writes at all. Temporarily booting Mu with fastboot does not
automatically transmit a Linux payload or a rootfs to Mu.

References
----------

* https://github.com/Project-Silicium/Mu-Silicium/blob/main/Status.md
* https://github.com/Project-Silicium/Guides/blob/main/General/OS/Arch-Linux/README.md
  (marked outdated upstream; use its EFI-chain explanation, not device-specific
  partition numbers or ACPI advice).
* https://docs.kernel.org/admin-guide/efi-stub.html

Partition layout and installation on UFS must be planned separately for the
actual handset. No repartitioning, flashing, erasing or bootloader-unlocking
commands are supplied or executed here.
