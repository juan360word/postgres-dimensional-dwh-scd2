
PSQL = docker compose exec -T db psql -U de -d tienda_online -v ON_ERROR_STOP=1 -q

up:
	docker compose up -d

psql:
	docker compose exec db psql -U de -d tienda_online

load:
	for f in sql/[1-6]_*.sql; do echo ">> $$f"; $(PSQL) < $$f || exit 1; done

simulate:
	$(PSQL) < sql/07_simular_cambios.sql

queries:
	$(PSQL) < sql/08_queries_analiticas.sql

test:
	$(PSQL) < sql/09_tests_calidad.sql

reset:
	docker compose down -v && docker compose up -d
