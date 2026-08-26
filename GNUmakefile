# GNUmakefile: canonical copy, owned by FuguBSD/Tooling.
all: check

-include mk/local.mk
include mk/org.mk
-include mk/perl.mk
-include mk/python.mk

check: $(CHECK_TARGETS)
lint: $(LINT_TARGETS)
format: $(FORMAT_TARGETS)
format-fix: $(FORMAT_FIX_TARGETS)
test: $(TEST_TARGETS)
.PHONY: all check lint format format-fix test
