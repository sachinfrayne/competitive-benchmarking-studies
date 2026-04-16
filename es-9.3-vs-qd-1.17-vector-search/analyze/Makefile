# Makefile for running Jingra analysis in Docker
# Analyzes ES 9.4 vs Qdrant 1.17 benchmark results

.PHONY: analyze clean help

# Docker image for Jingra
JINGRA_IMAGE ?= ghcr.io/elastic/jingra:latest

# Output directory (will be created if it doesn't exist)
OUTPUT_DIR := $(CURDIR)/output

# Source shared secrets from repo root (RESULTS_ES_* etc.) if present
-include ../secrets/.secrets.env

# Environment variables for results cluster access
RESULTS_ES_URL ?=
RESULTS_ES_USER ?=
RESULTS_ES_PASSWORD ?=

# Check if required environment variables are set
check-env:
	@if [ -z "$(RESULTS_ES_URL)" ]; then \
		echo "ERROR: RESULTS_ES_URL environment variable is not set"; \
		echo "Example: export RESULTS_ES_URL=https://results-cluster.example.com:9200"; \
		exit 1; \
	fi
	@if [ -z "$(RESULTS_ES_USER)" ]; then \
		echo "ERROR: RESULTS_ES_USER environment variable is not set"; \
		exit 1; \
	fi
	@if [ -z "$(RESULTS_ES_PASSWORD)" ]; then \
		echo "ERROR: RESULTS_ES_PASSWORD environment variable is not set"; \
		exit 1; \
	fi

# Create output directory
$(OUTPUT_DIR):
	@mkdir -p $(OUTPUT_DIR)
	@echo "Created output directory: $(OUTPUT_DIR)"

# Run analysis in Docker container
analyze: check-env $(OUTPUT_DIR)
	@echo "Running Jingra analysis in Docker..."
	@echo "Results cluster: $(RESULTS_ES_URL)"
	@echo "Output directory: $(OUTPUT_DIR)"
	@docker run --rm \
		-v $(CURDIR)/jingra.yml:/config/jingra.yml:ro \
		-v $(OUTPUT_DIR):/output \
		-e RESULTS_ES_URL="$(RESULTS_ES_URL)" \
		-e RESULTS_ES_USER="$(RESULTS_ES_USER)" \
		-e RESULTS_ES_PASSWORD="$(RESULTS_ES_PASSWORD)" \
		$(JINGRA_IMAGE) \
		analyze /config/jingra.yml
	@echo ""
	@echo "Analysis complete! Results written to: $(OUTPUT_DIR)"
	@echo ""
	@echo "Generated files:"
	@ls -lh $(OUTPUT_DIR)/*.csv 2>/dev/null || echo "  (no CSV files found)"

# Clean output directory
clean:
	@echo "Removing output directory: $(OUTPUT_DIR)"
	@rm -rf $(OUTPUT_DIR)
	@echo "Clean complete"

# Show help
help:
	@echo "Jingra Analysis Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make analyze     Run analysis in Docker (requires env vars)"
	@echo "  make clean       Remove output directory"
	@echo "  make help        Show this help message"
	@echo ""
	@echo ""
	@echo "Optional Variables:"
	@echo "  JINGRA_IMAGE         Docker image to use (default: $(JINGRA_IMAGE))"
	@echo ""
	@echo "Example:"
	@echo "  make analyze JINGRA_IMAGE=registry.example.com/jingra:172"
	@echo ""
	@echo "Output:"
	@echo "  CSV files will be written to: $(OUTPUT_DIR)"
	@echo "  - recall@X_comparison.csv (detailed comparisons)"
	@echo "  - summary_comparison.csv   (max recall points)"
	@echo "  - throughput_comparison.csv (QPS comparison)"
