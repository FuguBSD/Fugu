# mk/local.mk: the consumer hook of this repository (MK-LOCAL).
# sync never touches this file.

# Filesystem configuration
PREFIX		?= /usr/local
LIBDIR		?= $(PREFIX)/libdata/perl5/site_perl

# The full test tier set of make test
TEST_GLOBS	= t/fugu/*.t t/protocol/*.t t/conformance/*.t t/scripts/*.t t/ci/*.t

# The protocol coverage gate joins check
CHECK_TARGETS	+= spec-coverage

spec-coverage:
	@./scripts/spec-coverage --quiet --spec-dir spec/protocol

clean:
	rm -rf build
	rm -f *.tmp

install:
	# Install Perl libraries with their .pod sidecars.  Protocol/ is
	# a shared parent: other distributions live there too, so it is
	# created, never removed
	install -d $(DESTDIR)$(LIBDIR)/Fugu
	install -m 644 lib/Fugu/*.pm lib/Fugu/*.pod $(DESTDIR)$(LIBDIR)/Fugu/
	install -d $(DESTDIR)$(LIBDIR)/Protocol
	install -m 644 lib/Protocol/*.pm lib/Protocol/*.pod $(DESTDIR)$(LIBDIR)/Protocol/

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

.PHONY: spec-coverage clean install uninstall
