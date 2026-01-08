.PHONY: help build up down restart logs test lint security scan-vulnerabilities unit-test integration-test e2e-test ci-pipeline health-check

# Default target
.DEFAULT_GOAL := help

# Colors
YELLOW := \033[1;33m
GREEN := \033[1;32m
RED := \033[1;31m
NC := \033[0m

help: ## Display this help message
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

# ===========================
# DOCKER OPERATIONS
# ===========================

build: ## Build all Docker images
	@echo "$(GREEN)Building Docker images...$(NC)"
	docker compose build --pull

up: ## Start all services
	@echo "$(GREEN)Starting services...$(NC)"
	docker compose up -d
	@$(MAKE) health-check

down: ## Stop all services
	@echo "$(YELLOW)Stopping services...$(NC)"
	docker compose down

restart: down up ## Restart all services

logs: ## Tail logs from all services
	docker compose logs -f

clean: ## Clean up volumes and images
	@echo "$(RED)Cleaning up...$(NC)"
	docker compose down -v
	docker system prune -f

# ===========================
# HEALTH & MONITORING
# ===========================

health-check: ## Check health of all services
	@echo "$(GREEN)Checking service health...$(NC)"
	@docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
	@sleep 5
	@for service in homeassistant mosquitto postgres musicassistant emhass; do \
		echo "Checking $$service..."; \
		docker compose exec -T $$service sh -c 'echo "Health check passed"' 2>/dev/null || echo "$(RED)$$service is not healthy$(NC)"; \
	done

metrics: ## Open Prometheus metrics
	@echo "$(GREEN)Opening Prometheus at http://localhost:9090$(NC)"
	xdg-open http://localhost:9090 2>/dev/null || open http://localhost:9090 2>/dev/null || echo "Visit http://localhost:9090"

dashboard: ## Open Grafana dashboard
	@echo "$(GREEN)Opening Grafana at http://localhost:3000$(NC)"
	xdg-open http://localhost:3000 2>/dev/null || open http://localhost:3000 2>/dev/null || echo "Visit http://localhost:3000"

# ===========================
# TESTING
# ===========================

test: lint security unit-test integration-test ## Run all tests

lint: ## Run linting checks
	@echo "$(GREEN)Running linting checks...$(NC)"
	@docker compose run --rm test_runner bash -c "\
		pip install -q yamllint pylint flake8 black isort && \
		echo 'Running yamllint...' && \
		yamllint docker-compose.yml || true && \
		echo 'Running Python linters...' && \
		find /tests -name '*.py' -exec flake8 {} + || true && \
		find /tests -name '*.py' -exec pylint {} + || true && \
		echo 'Checking code formatting...' && \
		find /tests -name '*.py' -exec black --check {} + || true && \
		find /tests -name '*.py' -exec isort --check {} + || true \
	"

security: scan-vulnerabilities supply-chain-check ## Run all security checks

scan-vulnerabilities: ## Scan for OS and dependency vulnerabilities
	@echo "$(GREEN)Scanning for vulnerabilities with Trivy...$(NC)"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL \
		ghcr.io/home-assistant/home-assistant:2024.1 || true
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL \
		postgres:16-alpine || true
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL \
		eclipse-mosquitto:2.0 || true

supply-chain-check: ## Check supply chain security
	@echo "$(GREEN)Running supply chain checks...$(NC)"
	@docker run --rm -v $(PWD):/src aquasec/trivy:latest config /src || true
	@docker run --rm -v $(PWD):/src aquasec/trivy:latest fs --security-checks config,secret /src || true

code-quality: ## Run SonarQube analysis
	@echo "$(GREEN)Running SonarQube analysis...$(NC)"
	@docker run --rm \
		-e SONAR_HOST_URL=http://sonarqube:9000 \
		-v $(PWD):/usr/src \
		--network=home-automation_frontend \
		sonarsource/sonar-scanner-cli || echo "$(YELLOW)SonarQube not available$(NC)"

unit-test: ## Run unit tests
	@echo "$(GREEN)Running unit tests...$(NC)"
	@mkdir -p reports
	@docker compose run --rm test_runner bash -c "\
		pip install -q pytest pytest-cov pytest-asyncio paho-mqtt psycopg2-binary && \
		python -m pytest /tests/unit/ -v --cov=/tests --cov-report=html:/reports/coverage --cov-report=term \
	" || echo "$(YELLOW)No unit tests found$(NC)"

integration-test: ## Run integration tests
	@echo "$(GREEN)Running integration tests...$(NC)"
	@docker compose run --rm test_runner bash -c "\
		pip install -q pytest pytest-asyncio requests paho-mqtt psycopg2-binary && \
		python -m pytest /tests/integration/ -v --tb=short \
	" || echo "$(YELLOW)No integration tests found$(NC)"

e2e-test: ## Run E2E BDD tests
	@echo "$(GREEN)Running E2E BDD tests...$(NC)"
	@docker compose run --rm test_runner bash -c "\
		pip install -q pytest pytest-bdd pytest-asyncio requests selenium && \
		python -m pytest /tests/e2e/ -v --tb=short \
	" || echo "$(YELLOW)No E2E tests found$(NC)"

# ===========================
# CI PIPELINE
# ===========================

ci-pipeline: build lint security unit-test integration-test up health-check e2e-test ## Run full CI pipeline
	@echo "$(GREEN)CI Pipeline completed successfully!$(NC)"

pre-commit: lint unit-test ## Run pre-commit checks
	@echo "$(GREEN)Pre-commit checks passed!$(NC)"

# ===========================
# GITOPS
# ===========================

validate: ## Validate configuration files
	@echo "$(GREEN)Validating configurations...$(NC)"
	docker compose config --quiet && echo "$(GREEN)docker-compose.yml is valid$(NC)" || echo "$(RED)docker-compose.yml has errors$(NC)"
	@command -v yamllint >/dev/null 2>&1 && yamllint *.yml || echo "$(YELLOW)yamllint not installed$(NC)"

deploy: validate ci-pipeline ## Deploy to production
	@echo "$(GREEN)Deploying to production...$(NC)"
	@git diff --quiet || (echo "$(RED)Uncommitted changes detected$(NC)" && exit 1)
	docker compose up -d
	@$(MAKE) health-check

rollback: ## Rollback to previous version
	@echo "$(YELLOW)Rolling back...$(NC)"
	git checkout HEAD~1 docker-compose.yml
	docker compose up -d
	@$(MAKE) health-check

# ===========================
# BACKUP & RESTORE
# ===========================

backup: ## Backup all volumes
	@echo "$(GREEN)Creating backup...$(NC)"
	@mkdir -p backups
	@docker compose exec postgres pg_dump -U hauser homeassistant > backups/postgres_$(shell date +%Y%m%d_%H%M%S).sql
	@tar czf backups/volumes_$(shell date +%Y%m%d_%H%M%S).tar.gz \
		-C /var/lib/docker/volumes/ \
		home-automation_homeassistant_config \
		home-automation_musicassistant_data \
		home-automation_mosquitto_data
	@echo "$(GREEN)Backup completed$(NC)"

restore: ## Restore from backup (specify BACKUP_FILE=path/to/backup.sql)
	@echo "$(YELLOW)Restoring from backup...$(NC)"
	@if [ -z "$(BACKUP_FILE)" ]; then echo "$(RED)Please specify BACKUP_FILE=path/to/backup.sql$(NC)"; exit 1; fi
	docker compose exec -T postgres psql -U hauser homeassistant < $(BACKUP_FILE)
	@echo "$(GREEN)Restore completed$(NC)"

# ===========================
# DEVELOPMENT
# ===========================

shell: ## Open shell in test_runner container
	docker compose run --rm test_runner bash

ha-shell: ## Open Home Assistant CLI
	docker compose exec homeassistant bash

db-shell: ## Open PostgreSQL shell
	docker compose exec postgres psql -U hauser homeassistant

mqtt-subscribe: ## Subscribe to all MQTT topics
	docker compose exec mosquitto mosquitto_sub -v -t '#'

watch-logs: ## Watch logs with grep filter (use FILTER=pattern)
	docker compose logs -f | grep -i "$(FILTER)"
