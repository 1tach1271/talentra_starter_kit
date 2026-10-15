# Talentra Database Design Hackathon
Team: Shashi (Member A), Kudrat (Member B), Kshitij (Member C). Engine: PostgreSQL 16.

## Quick start
    docker compose up -d
    psql postgresql://talentra:talentra@localhost:5432/talentra -f schema/000_setup.sql
    psql postgresql://talentra:talentra@localhost:5432/talentra -f schema/010_master_data.sql

## Folders
docs/ decisions and documents | schema/ numbered DDL files | seed/ generators
queries/ query set | perf/ benchmarks | security/ RLS, threat model, tests

## Git rules
- main is protected. Work on feature/<name>-<module>. Merge via pull request.
- Every PR is reviewed by a teammate (this is the "validate" step in the docket).
- Schema files are numbered so they run in order: 000, 010, 020 ...
