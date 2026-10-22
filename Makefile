SCM ?= $(HOME)/devel/scm/target/release/scm

.PHONY: check builtins
check:                  ## parse, compile the queries, check the spellings
	SCM=$(SCM) ./scripts/check.sh

builtins:               ## regenerate the builtin list from a live scm
	SCM=$(SCM) ./scripts/gen-builtins.sh
