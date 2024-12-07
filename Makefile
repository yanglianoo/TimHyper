SHELL:=bash
ARCH=aarch64
TimHyper:=$(abspath .)

CROSS_COMPILE:=/home/timer/arm-toolchain/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-elf/bin/aarch64-none-elf-

wrkdir:=$(TimHyper)/wkdir
wrkdir_src:=$(wrkdir)/srcs
wrkdir_bin:=$(wrkdir)/bin
wrkdir_imgs:=$(wrkdir)/imgs
wrkdir_plat_imgs:=$(wrkdir_imgs)

wrkdirs=$(wrkdir) $(wrkdir_src) $(wrkdir_bin) $(wrkdir_plat_imgs) 

# 创建工作文件夹
ifeq ($(filter clean distclean, $(MAKECMDGOALS)),)
$(shell mkdir -p $(wrkdirs))
endif

# 编译uboot
include ./uboot.mk
uboot_defconfig:=qemu_arm64_defconfig
uboot_cfg_frag:="CONFIG_SYS_TEXT_BASE=0x60000000\nCONFIG_TFABOOT=y\n"
uboot_image:=$(wrkdir_plat_imgs)/u-boot.bin
$(eval $(call build-uboot, $(uboot_image), $(uboot_defconfig), $(uboot_cfg_frag)))

# 编译ATF-A
include ./atf.mk
atf_plat:=qemu
atf_targets:=bl1 fip 
atf_flags+=BL33=$(wrkdir_plat_imgs)/u-boot.bin
atf_flags+=QEMU_USE_GIC_DRIVER=QEMU_GICV3

atf-fip:=$(wrkdir_plat_imgs)/flash.bin
$(atf-fip): $(atf_src) $(uboot_image) 
	$(MAKE) -C $(atf_src) PLAT=$(atf_plat) $(atf_targets) $(atf_flags) 
	dd if=$(atf_src)/build/qemu/release/bl1.bin of=$(atf-fip)
	dd if=$(atf_src)/build/qemu/release/fip.bin of=$(atf-fip) seek=64 bs=4096 conv=notrunc

platform: $(atf-fip)


qemu_arch:=$(ARCH)
qemu_cmd:=qemu-system-$(qemu_arch)

run: platform
	@$(qemu_cmd) -nographic\
		-M virt,secure=on,virtualization=on,gic-version=3 \
		-cpu cortex-a53 -smp 4 -m 4G\
		-bios $(atf-fip)\

distclean:
	rm -rf $(wrkdir)

.PHONY: run