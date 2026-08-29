# The org pack of FuguBSD/Tooling owns this file. Do not edit a
# synced copy. Edit the canonical copy in FuguBSD/Tooling.
#
# The org fragment: the specification gates, the prose gate, the
# gitleaks gate, the test runner, the deps targets, and the Markdown
# formatting pair. The fragment uses the portable make subset, so
# every dispatcher includes it without change.

SPEC_CHECK	?= scripts/spec-check
STE_LINT	?= scripts/ste-lint
DEPS		?= scripts/deps
GITLEAKS	?= gitleaks
PRETTIER	?= bunx prettier@3.9.6
PROVE		?= prove -l
TEST_GLOBS	?= t/ci/*.t

CHECK_TARGETS		+= lint format test spec-check ste-lint gitleaks
TEST_TARGETS		+= test-prove
FORMAT_TARGETS		+= format-md
FORMAT_FIX_TARGETS	+= format-md-fix

spec-check:
	@$(SPEC_CHECK)

ste-lint:
	@$(STE_LINT)

# The gitleaks gate runs three scans: the git history, the unstaged
# changes to the tracked files, and the staged changes (MK-GITLEAKS).
# --redact keeps a found secret out of the terminal and the CI log.
gitleaks:
	@$(GITLEAKS) git --no-banner --redact -v --log-level warn .
	@$(GITLEAKS) git --no-banner --redact -v --log-level warn --pre-commit .
	@$(GITLEAKS) git --no-banner --redact -v --log-level warn --pre-commit --staged .

test-prove:
	$(PROVE) $(TEST_GLOBS)

# The deps targets install the dependencies that deps/<OS>.txt names.
# Without a manifest, scripts/deps reports and exits zero.
deps:
	$(DEPS) runtime

deps-test: deps
	$(DEPS) test

deps-develop: deps deps-test
	$(DEPS) develop

# The Markdown formatting pair runs prettier through bunx, per
# MK-VERBS-5.
format-md:
	@$(PRETTIER) --check --no-error-on-unmatched-pattern '**/*.md' '**/*.json' '**/*.yml' || { echo "Run 'make format-md-fix' to fix formatting"; exit 1; }

format-md-fix:
	$(PRETTIER) --write --no-error-on-unmatched-pattern '**/*.md' '**/*.json' '**/*.yml'

.PHONY: spec-check ste-lint gitleaks test-prove deps deps-test deps-develop
.PHONY: format-md format-md-fix
