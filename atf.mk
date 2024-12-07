atf_repo:=https://github.com/bao-project/arm-trusted-firmware.git
atf_src:=$(wrkdir_src)/arm-trusted-firmware-$(ARCH)
atf_version:=bao/demo

$(atf_src):
	git clone --depth 1 --branch $(atf_version) $(atf_repo) $(atf_src)

