.PHONY: ingest snapshot build build-prod freshness docs blog dags lint fix pipeline sync install

SOURCE ?= jaffle_shop

ingest:
	python dlt/pipeline.py $(SOURCE)

snapshot:
	cd dbt && dbt snapshot --profiles-dir .

build:
	cd dbt && dbt build --profiles-dir .

build-prod:
	cd dbt && dbt build --profiles-dir . --target prod

freshness:
	cd dbt && dbt source freshness --profiles-dir .

docs:
	cd dbt && dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .

blog:
	mkdir -p .mkdocs && curl -sSfL -o .mkdocs/base.yml https://raw.githubusercontent.com/mazino2d/github-workflows/v1/mkdocs/base.yml
	mkdocs serve

dags:
	python -m dag.render

lint:
	sqlfluff lint dbt/models

fix:
	sqlfluff fix dbt/models

pipeline:
	$(MAKE) ingest && $(MAKE) snapshot && $(MAKE) build

sync:
	pip-compile pyproject.toml -o requirements.txt

install:
	pip install -e ".[dev]"
