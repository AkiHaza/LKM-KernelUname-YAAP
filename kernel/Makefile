KDIR ?=
MDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

.PHONY: all clean

all:
	@test -n "$(KDIR)" || (echo "KDIR is required" >&2; exit 1)
	$(MAKE) -C $(KDIR) M=$(MDIR) src=$(MDIR) modules

clean:
	@test -n "$(KDIR)" || (echo "KDIR is required" >&2; exit 1)
	$(MAKE) -C $(KDIR) M=$(MDIR) clean
