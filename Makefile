include Makefile.vars.mk

.PHONY: install-arch
install-arch:
	sudo pacman --noconfirm -S $(TELEPORT_DEPENDENCY_ARCH)