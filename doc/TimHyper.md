# 一 Bao Hypervisor 环境搭建与运行

官网：[Bao Project](https://github.com/bao-project)

## 1.1 环境准备

个人环境：

- 宿主机：`wsl2 ubuntu20.04`

- 编译器：[Arm GNU Toolchain Downloads – Arm Developer](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)

  ![image-20241121164101383](image/image-20241121164101383.png)

软件依赖：

```shell
sudo apt-get update
sudo apt install build-essential bison flex git libssl-dev ninja-build \
    u-boot-tools pandoc libslirp-dev pkg-config libglib2.0-dev libpixman-1-dev \
    gettext-base curl xterm cmake python3-pip xilinx-bootgen

pip3 install pykwalify packaging pyelftools
```

## 1.2 编译运行

1.先进入`root`模式

```shell
sudo su
```

2.需要设置`CROSS_COMPILE`为你自己的编译器的目录，使用`qemu-aarch64-virt`作为运行soc，运行`linux`加上`freertos`

```shell
export CROSS_COMPILE=/path/to/toolchain/install/dir/bin/your-toolchain-prefix-
export PLATFORM=qemu-aarch64-virt
export DEMO=linux+freertos
```

3.代码仓库下载

```shell
git clone https://github.com/bao-project/bao-demos
cd bao-demos
```

4.编译，需要花点时间

```shell
make -j$(nproc)
```

![image-20241122165120263](image/image-20241122165120263.png)

5.运行

```shell
make PLATFORM=qemu-aarch64-virt DEMO=linux+freertos run
```

启动后有如下的提示：

![image-20241122170324850](image/image-20241122170324850.png)

我们运行了`Linux+FreeRtos`，可以`go 0x50000000`跳转到`bao`的`image`执行，这里应该是运行的`freertos`

<img src="image/image-20241122170924308.png" alt="image-20241122170924308" style="zoom:67%;" />

新开一个终端通过`ssh root@localhost -p 5555`来进入`Linux`

![image-20241122170512433](image/image-20241122170512433.png)

用户名和密码都是`root`

![image-20241122171821770](image/image-20241122171821770.png)

`/dev/baoipc0`是FreeRtos和Linux的共享内存的文件描述符，可以向此设备写入数据，FreeRtos那边会进行打印

```shell
echo "Hello, Bao!" > /dev/baoipc0
```

<img src="image/image-20241122171949277.png" alt="image-20241122171949277" style="zoom:50%;" />



## 1.3 问题记录

![image-20241121163940953](image/image-20241121163940953.png)

- 进`root`模式编译，看网上是wsl2编译`BuildRoot`的问题

![image-20241122164909289](image/image-20241122164909289.png)

- 下载`uboot`总是下载不下来，网络不行，按照网上的教程设置一下`git`，百度一下这个错误就好

![image-20241122172047079](image/image-20241122172047079.png)

- 第二次通过`ssh root@localhost -p 5555`进入`Linux`时，会进不去，这是ssh的原因，他其实给出了解决办法，输入`remove with`下面的指令即可

  ```shell
  ssh-keygen -f "/home/timer/.ssh/known_hosts" -R "[localhost]:5555"
  ```

## 参考链接

- [bao-demos构建与与运行逻辑 | Personal Blog](https://zq.org.edu.kg/2024/01/05/bao-demos构建与与运行逻辑/)
- [Bao Hypervisor移植与验证 - clark.yang - Confluence](https://autocore.atlassian.net/wiki/spaces/~712020c17ba14ea02d499a9b11861fe945a652/blog/2023/10/27/324538457/Bao+Hypervisor)

# 二 Bao 项目编译框架

项目的工程目录如下：

<img src="image/image-20241129155001201.png" alt="image-20241129155001201" style="zoom:67%;" />

上面的编译过程是通过主目录这个`Makefile`来控制的，编译我们传入的参数如下：

```shell
export CROSS_COMPILE=/path/to/toolchain/install/dir/bin/your-toolchain-prefix-
export PLATFORM=qemu-aarch64-virt
export DEMO=linux+freertos
```

这些参数都会被此`Makefile`用到，主`Makefile`会去包含`paltform`目录下的`Makefile`

```makefile
bao_demos:=$(abspath .)
platform_dir:=$(bao_demos)/platforms/$(PLATFORM)
demo_dir:=$(bao_demos)/demos/$(DEMO)
SHELL:=/bin/bash
ifeq ($(wildcard $(platform_dir)),)
 $(error Target platform $(PLATFORM) is not supported)
endif
ifeq ($(wildcard $(demo_dir)),)
 $(error Target demo $(DEMO) is not supported)
endif
include $(platform_dir)/make.mk
include $(demo_dir)/make.mk
```

<img src="image/image-20241129155552223.png" alt="image-20241129155552223" style="zoom:67%;" />

我们使用的就是`platform/qemu-aarch64-virt/`目录下这个`makefile`

```makefile
ARCH:=aarch64

include $(bao_demos)/platforms/qemu.mk

include $(bao_demos)/platforms/uboot.mk
uboot_defconfig:=qemu_arm64_defconfig
uboot_cfg_frag:="CONFIG_SYS_TEXT_BASE=0x60000000\nCONFIG_TFABOOT=y\n"
uboot_image:=$(wrkdir_plat_imgs)/u-boot.bin
$(eval $(call build-uboot, $(uboot_image), $(uboot_defconfig), $(uboot_cfg_frag)))

atf_plat:=qemu
atf_targets:=bl1 fip 
atf_flags+=BL33=$(wrkdir_plat_imgs)/u-boot.bin
atf_flags+=QEMU_USE_GIC_DRIVER=QEMU_GICV3
include $(bao_demos)/platforms/atf.mk

atf-fip:=$(wrkdir_plat_imgs)/flash.bin
$(atf-fip): $(uboot_image) $(atf_src)
	$(MAKE) -C $(atf_src) PLAT=$(atf_plat) $(atf_targets) $(atf_flags)
	dd if=$(atf_src)/build/qemu/release/bl1.bin of=$(atf-fip)
	dd if=$(atf_src)/build/qemu/release/fip.bin of=$(atf-fip) seek=64 bs=4096 conv=notrunc


platform: $(bao_image) $(atf-fip) 

instuctions:=$(bao_demos)/platforms/$(PLATFORM)/README.md
run: qemu platform
	$(call print-instructions, $(instuctions), 1, false)
	@$(qemu_cmd) -nographic\
		-M virt,secure=on,virtualization=on,gic-version=3 \
		-cpu cortex-a53 -smp 4 -m 4G\
		-bios $(atf-fip)\
		-device loader,file="$(bao_image)",addr=0x50000000,force-raw=on\
		-device virtio-net-device,netdev=net0\
		-netdev user,id=net0,net=192.168.42.0/24,hostfwd=tcp:127.0.0.1:5555-:22\
		-device virtio-serial-device -chardev pty,id=serial3 -device virtconsole,chardev=serial3
	

.PHONY: run
```

在主目录下的`makefile`中定义了：

```makefile
all: platform 
```

假设我们执行`make`命令，那么会先去执行`platform`即此`makefile`中定义的

```makefile
platform: $(bao_image) $(atf-fip) 
```

`platform`目标依赖了两个目标`bao_image`和`atf-fip`，`bao_image`目标是主目录下的`makefile`定义的，目的用于生成`bao.bin`

```makefile
bao_image:=$(wrkdir_demo_imgs)/bao.bin
```

![image-20241129160821101](image/image-20241129160821101.png)

我们再来看`atf-fip`这个目标：为了生成`flash.bin`，依赖`uboot_image`和`atf_src`

![image-20241129160922496](image/image-20241129160922496.png)

先看`atf_src`

```makefile
atf_plat:=qemu
atf_targets:=bl1 fip 
atf_flags+=BL33=$(wrkdir_plat_imgs)/u-boot.bin
atf_flags+=QEMU_USE_GIC_DRIVER=QEMU_GICV3
include $(bao_demos)/platforms/atf.mk
```

`platform/qemu-aarch64-virt/Makefile`会去包含`$(bao_demos)/platforms/atf.mk`

```makefile
atf_repo:=https://github.com/bao-project/arm-trusted-firmware.git
atf_src:=$(wrkdir_src)/arm-trusted-firmware-$(ARCH)
atf_version:=bao/demo

$(atf_src):
	git clone --depth 1 --branch $(atf_version) $(atf_repo) $(atf_src)

define build-atf
$(strip $1): $(atf_src)
	$(MAKE) -C $(atf_src) bl31 PLAT=$(strip $2) $(strip $3)
	cp $(atf_src)/build/$(strip $2)/release/bl31.bin $$@
endef
```

可以看见`atf_src`目标做的事情是下载`arm-trusted-firmware`到`$(wrkdir_src)/arm-trusted-firmware-$(ARCH)`目录下

我们再回到`platform/qemu-aarch64-virt/Makefile`来看`uboot_image`这个目标

![image-20241129162007571](image/image-20241129162007571.png)

`uboot_image:=$(wrkdir_plat_imgs)/u-boot.bin`这里就是去生成`uboot`的二进制文件，如何编译执行的呢，是通过`$(eval $(call build-uboot, $(uboot_image), $(uboot_defconfig), $(uboot_cfg_frag)))`

这条指令去调用`build-uboot`来实现的，这个指令定义在`uboot.mk`中

```makefile
uboot_repo:=https://github.com/u-boot/u-boot.git
uboot_version:=v2022.10
uboot_src:=$(wrkdir_src)/u-boot

$(uboot_src):
	git clone --depth 1 --branch $(uboot_version) $(uboot_repo) $(uboot_src)

define build-uboot
$(strip $1): $(uboot_src)
	$(MAKE) -C $(uboot_src) $(strip $2)
	echo $(strip $3) >> $(uboot_src)/.config
	$(MAKE) -C $(uboot_src) -j$(nproc) 
	cp $(uboot_src)/u-boot.bin $$@
endef

u-boot: $(wrkdir_plat_imgs)/u-boot.bin
```

此`Makefile`会去下载`2022.10`版本的`uboot`，然后定义一个`build-uboot`的指令，结合上面的call传入的参数去编译执行

ok我们再回到`platform/qemu-aarch64-virt/Makefile`

```makefile
atf-fip:=$(wrkdir_plat_imgs)/flash.bin
$(atf-fip): $(uboot_image) $(atf_src)
	$(MAKE) -C $(atf_src) PLAT=$(atf_plat) $(atf_targets) $(atf_flags)
	dd if=$(atf_src)/build/qemu/release/bl1.bin of=$(atf-fip)
	dd if=$(atf_src)/build/qemu/release/fip.bin of=$(atf-fip) seek=64 bs=4096 conv=notrunc
```

这里会去编译`arm-trusted-firmware`，然后把`arm-trusted-firmware`的固件通过`dd`命令合并成`flash.bin`

到此我们已经编译生成了`flash.bin`和`uboot.bin`，现在回到主目录下的`makefile`，现在要来看`bao_image`这个目标

```makefile
bao $(bao_image): $(guest_images) $(bao_cfg) $(bao_src) 
	$(MAKE) -C $(bao_src)\
		PLATFORM=$(PLATFORM)\
		CONFIG_REPO=$(bao_cfg_repo)\
		CONFIG=$(DEMO) \
		CPPFLAGS=-DBAO_DEMOS_WRKDIR_IMGS=$(wrkdir_demo_imgs)
	cp $(bao_src)/bin/$(PLATFORM)/$(DEMO)/bao.bin $(bao_image)
```

`bao_image`以来了`guest_images`、`bao_cfg`、`bao_src`这三个目标，`guest_images`实际上就是去编译生成两个os的image，即`linux`和 `freertos`，`bao_cfg`、`bao_src`这两个目标就是去仓库下载`bao`的源码，然后通过下面的指令编译生成`bao.bin`，至此我们生成的文件有：`bao.bin`、`uboot.bin`、`flash.bin`、`freertos.bin`、`linux.bin`，编译完成后我们是通过`make run`指令来运行的，`run`这个目标定义在`platform/qemu-aarch64-virt/Makefile`里

![image-20241129164128735](image/image-20241129164128735.png)

# 三 TimHyper项目框架搭建

根据上面对`bao`项目的编译框架的剖析，我们来搭建自己项目的框架

