# mk/perl.mk: canonical copy, owned by FuguBSD/Tooling.
# The perl fragment: lint, format, dist, and the dependency targets.
# The fragment uses the portable make subset, so every dispatcher
# includes it without change.

PERL_SRC_DIRS	?= lib scripts
DEPS		?= scripts/deps
DIST		?= scripts/dist
VERSION		?=

# Every Perl source under the source directories: modules and tests
# by extension, executables by shebang. Perl::Critic and Perl::Tidy
# select files the same way, so lint and format cover the same set.
PERL_SRC	= find $(PERL_SRC_DIRS) -type f \( -name '*.pm' -o \
		  -name '*.t' -o \
		  -exec sh -c 'head -1 "$$1" | grep -q "^\#!.*perl"' \
		  _ {} \; \) -print

PERLTIDY	?= perl -MPerl::Tidy -e 'Perl::Tidy::perltidy()'

LINT_TARGETS		+= lint-perl
FORMAT_TARGETS		+= format-perl
FORMAT_FIX_TARGETS	+= format-perl-fix

lint-perl:
	@$(PERL_SRC) | xargs perl -MPerl::Critic::Command -e 'exit Perl::Critic::Command::run()' -- --severity 4 --verbose 8

format-perl:
	@$(PERL_SRC) | while read f; do \
		$(PERLTIDY) -- --standard-output "$$f" | diff -q "$$f" - >/dev/null 2>&1 || echo "$$f"; \
	done | grep . && echo "Run 'make format-perl-fix' to fix formatting" && exit 1 || echo "All files formatted correctly"

format-perl-fix:
	@$(PERL_SRC) | while read f; do \
		$(PERLTIDY) -- -b -bext='/' "$$f"; \
	done

# scripts/dist treats an empty --version value as absent and derives
# the version from the latest tag. CI passes VERSION, so the tag and
# the tarball agree.
dist:
	@$(DIST) --version '$(VERSION)'

deps:
	$(DEPS) runtime

deps-test: deps
	$(DEPS) test

deps-develop: deps deps-test
	$(DEPS) develop

.PHONY: lint-perl format-perl format-perl-fix dist deps deps-test deps-develop
