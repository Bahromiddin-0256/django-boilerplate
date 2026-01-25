# Makefile for Django Docker Development
.PHONY: help build dev test prod up down logs shell migrate makemigrations createsuperuser clean

# Default target
help:
	@echo "Available commands:"
	@echo ""
	@echo "  Development:"
	@echo "    make dev              - Start development environment"
	@echo "    make dev-build        - Build and start development environment"
	@echo "    make dev-tools        - Start dev environment with pgadmin & mailpit"
	@echo ""
	@echo "  Testing:"
	@echo "    make test             - Run tests"
	@echo "    make test-build       - Build and run tests"
	@echo "    make test-coverage    - Run tests with coverage"
	@echo ""
	@echo "  Production:"
	@echo "    make prod             - Start production environment"
	@echo "    make prod-build       - Build and start production environment"
    @echo "    make prod-migrate     - Run database migrations production"
	@echo "    make prod-makemigrations   - Create new migrations production"
	@echo ""
	@echo "  Common:"
	@echo "    make build            - Build all Docker images"
	@echo "    make down             - Stop all containers"
	@echo "    make logs             - View container logs"
	@echo "    make shell            - Open Django shell"
	@echo "    make bash             - Open bash in web container"
	@echo "    make dev-migrate      - Run database migrations development"
	@echo "    make dev-makemigrations   - Create new migrations"
	@echo "    make createsuperuser  - Create Django superuser"
	@echo "    make collectstatic    - Collect static files"
	@echo "    make clean            - Remove all containers, volumes, and images"

# =============================================================================
# Development
# =============================================================================
dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up

dev-build:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

dev-tools:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml --profile tools up

dev-detach:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# =============================================================================
# Testing
# =============================================================================
test:
	docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm web

test-build:
	docker compose -f docker-compose.yml -f docker-compose.test.yml build
	docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm web

test-coverage:
	docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm web coverage run manage.py test
	docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm web coverage report

test-integration:
	docker compose -f docker-compose.yml -f docker-compose.test.yml --profile integration up --abort-on-container-exit

# =============================================================================
# Production
# =============================================================================
prod:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

prod-build:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

prod-logs:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f

# =============================================================================
# Build
# =============================================================================
build:
	docker compose build

build-dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml build

build-test:
	docker compose -f docker-compose.yml -f docker-compose.test.yml build

build-prod:
	docker compose -f docker-compose.yml -f docker-compose.prod.yml build

# =============================================================================
# Container Management
# =============================================================================
down:
	docker compose down

down-volumes:
	docker compose down -v

logs:
	docker compose logs -f

logs-web:
	docker compose logs -f web

# =============================================================================
# Django Commands
# =============================================================================
shell:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec web python manage.py shell

bash:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec web bash

dev-migrate:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec web python manage.py migrate

dev-makemigrations:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec web python manage.py makemigrations

createsuperuser:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec web python manage.py createsuperuser

collectstatic:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec web python manage.py collectstatic --noinput

# =============================================================================
# Database
# =============================================================================
db-shell:
	docker compose exec db psql -U $${DB_USER:-postgres} -d $${DB_NAME:-django_db}

db-backup:
	docker compose exec db pg_dump -U $${DB_USER:-postgres} $${DB_NAME:-django_db} > backup_$$(date +%Y%m%d_%H%M%S).sql

db-restore:
	@read -p "Enter backup file name: " file; \
	docker compose exec -T db psql -U $${DB_USER:-postgres} -d $${DB_NAME:-django_db} < $$file

# =============================================================================
# Cleanup
# =============================================================================
clean:
	docker compose down -v --rmi local --remove-orphans
	docker system prune -f

clean-all:
	docker compose down -v --rmi all --remove-orphans
	docker system prune -af