# Image du service dbt (profil Compose "transfo").
# Le dossier s4/ n'était pas présent dans le kit reçu : Dockerfile reconstruit
# par le groupe, avec des versions figées pour rester reproductible.
FROM python:3.12-slim
# git : requis par « dbt debug » (et par « dbt deps » si on ajoute des packages).
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir dbt-core==1.9.4 dbt-postgres==1.9.0
WORKDIR /work
