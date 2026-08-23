# mk/org.mk: canonical copy, owned by FuguBSD/Tooling.
# The org fragment: the specification gates, the prose gate, the test
# runner, and the Markdown formatting pair. The fragment uses the
# portable make subset, so every dispatcher includes it without change.

SPEC_CHECK	?= scripts/spec-check
STE_LINT	?= scripts/ste-lint
PRETTIER	?= npx prettier@3.9.6
PROVE		?= prove -l
TEST_GLOBS	?= t/ci/*.t

CHECK_TARGETS	+= lint format test spec-check ste-lint
TEST_TARGETS	+= test-prove

spec-check:
	@$(SPEC_CHECK)

ste-lint:
	@$(STE_LINT)

test-prove:
	$(PROVE) $(TEST_GLOBS)

# format-md and format-md-fix stay out of every aggregate: prettier
# runs through npx, and no deps manifest provides node. CI runs
# format-md in its own job.
format-md:
	@$(PRETTIER) --check --no-error-on-unmatched-pattern '**/*.md' '**/*.json' '**/*.yml' || { echo "Run 'make format-md-fix' to fix formatting"; exit 1; }

format-md-fix:
	$(PRETTIER) --write --no-error-on-unmatched-pattern '**/*.md' '**/*.json' '**/*.yml'

.PHONY: spec-check ste-lint test-prove format-md format-md-fix
