.PHONY: all build check clean deps deps-develop deps-test dist install lint prettier prettier-fix spec-check spec-coverage ste-lint test tidy tidy-fix uninstall

# Filesystem configuration
PREFIX			?= /usr/local
LIBDIR			?= $(PREFIX)/libdata/perl5/site_perl

# Build configuration.  The version derives from the latest semantic
# version tag, without the leading v.  There is no VERSION file.
VERSION			?= $(shell (git describe --tags --match 'v*' --abbrev=0 2>/dev/null || echo v0.0.0) | sed 's/^v//')
DIST			= Fugu
TARBALL			= $(DIST)-$(VERSION).tar.gz

# Build tools
PERLTIDY		= perl -MPerl::Tidy -e 'Perl::Tidy::perltidy()'
# Pin the version so that local runs and CI agree on formatting
PRETTIER		= npx prettier@3.9.6

# Every Perl source in the tree: modules by extension, executables by
# shebang.  Files in scripts/ carry no extension, because a tool's
# name does not encode its language.  Thus the shebang identifies
# them.  Perl::Critic selects files the same way.  lint and tidy
# therefore cover the same set, with no list to keep true.
PERLSRC			= find lib scripts -type f \( -name '*.pm' -o \
			  -exec sh -c 'head -1 "$$1" | grep -q "^\#!.*perl"' \
			  _ {} \; \) -print

DEPS			= scripts/deps

all: deps check

build: dist

# prettier stays out of check: it runs through npx, and no deps/
# manifest provides node. CI runs it in its own job.
check: lint test tidy spec-coverage spec-check ste-lint

clean:
	rm -rf build
	rm -f *.tmp

deps:
	$(DEPS) runtime

deps-develop: deps deps-test
	$(DEPS) develop

deps-test: deps
	$(DEPS) test

# The dist tarball is a standard Perl distribution: Makefile.PL,
# MANIFEST, lib/ and the test tiers that run from a dist tree. CI
# attaches it to each release, and consumers install it with cpanm.
dist:
	@./scripts/dist --version $(VERSION)

install:
	# Install Perl libraries with their .pod sidecars.  Protocol/ is
	# a shared parent: other distributions live there too, so it is
	# created, never removed
	install -d $(DESTDIR)$(LIBDIR)/Fugu
	install -m 644 lib/Fugu/*.pm lib/Fugu/*.pod $(DESTDIR)$(LIBDIR)/Fugu/
	install -d $(DESTDIR)$(LIBDIR)/Protocol
	install -m 644 lib/Protocol/*.pm lib/Protocol/*.pod $(DESTDIR)$(LIBDIR)/Protocol/

lint:
	@$(PERLSRC) | xargs perl -MPerl::Critic::Command -e 'Perl::Critic::Command::run()' -- --severity 4 --verbose 8

prettier:
	@$(PRETTIER) --check --no-error-on-unmatched-pattern '**/*.md' '**/*.json' '**/*.yml' || { echo "Run 'make prettier-fix' to fix formatting"; exit 1; }

prettier-fix:
	$(PRETTIER) --write --no-error-on-unmatched-pattern '**/*.md' '**/*.json' '**/*.yml'

spec-check:
	@./scripts/spec-check

spec-coverage:
	@./scripts/spec-coverage --quiet --spec-dir spec/protocol

ste-lint:
	@./scripts/ste-lint

test:
	prove -l -v t/fugu/*.t
	prove -l -v t/protocol/*.t
	prove -l -v t/conformance/*.t
	prove -l -v t/scripts/*.t
	prove -l -v t/ci/*.t

tidy:
	@$(PERLSRC) | while read f; do \
		$(PERLTIDY) -- --standard-output "$$f" | diff -q "$$f" - >/dev/null 2>&1 || echo "$$f"; \
	done | grep . && echo "Run 'make tidy-fix' to fix formatting" && exit 1 || echo "All files formatted correctly"

tidy-fix:
	@$(PERLSRC) | while read f; do \
		$(PERLTIDY) -- -b -bext='/' "$$f"; \
	done

uninstall:
	# Remove Perl libraries.  Protocol/ is a shared parent: any
	# other Protocol:: distribution lives beside ours.  Remove what
	# this project owns, then rmdir the parent, which fails
	# harmlessly when it still holds something
	rm -rf $(DESTDIR)$(LIBDIR)/Fugu
	# The loop derives the list from the source tree.  A new
	# top-level Protocol:: module is thus removed with no second
	# place to keep true
	for f in lib/Protocol/*.pm lib/Protocol/*.pod; do \
		rm -f "$(DESTDIR)$(LIBDIR)/Protocol/$${f##*/}"; \
	done
	-rmdir $(DESTDIR)$(LIBDIR)/Protocol 2>/dev/null
