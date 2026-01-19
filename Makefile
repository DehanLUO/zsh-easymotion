.PHONY: test unit integration update-test-numbers clean

# Default test target runs both unit and integration tests
test: unit integration

# Run unit tests
unit:
	@echo "Running unit tests..."
	@zunit tests/unit.zunit

# Run integration tests
integration:
	@echo "Running integration tests..."
	@zunit tests/integration.zunit

# Update test numbering in both unit and integration test files
renumber:
	@echo "Updating test numbers..."
	@zsh scripts/renumber-tests.zsh \
		tests/unit.zunit \
		tests/integration.zunit

# Help target
help:
	@echo "Available targets:"
	@echo "  test        - Run all tests"
	@echo "  unit        - Run unit tests only"
	@echo "  integration - Run integration tests only"
	@echo "  renumber    - Update test numbering in test files"
	@echo "  help        - Show this help message"

# Show help by default when running just 'make'
.DEFAULT_GOAL := help
