COMMENT =	OpenBSD-style daemon utilities for Perl

DISTNAME =	Fugu-0.5.2
CPAN_AUTHOR =	SENZILLA

CATEGORIES =	devel perl5

# ISC
PERMIT_PACKAGE =	Yes

MODULES =		cpan

# The library loads with core Perl only, so the port has no run
# dependency. Each test dependency backs a test that skips without
# its tool.
TEST_DEPENDS =		net/curl \
			net/p5-Net-SSH2 \
			net/wget \
			security/gnupg \
			www/p5-URI

PKG_ARCH =		*

.include <bsd.port.mk>
