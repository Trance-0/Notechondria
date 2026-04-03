# Jenkins full-stack deployment

This deployment target uses Jenkins to test and deploy the full stack:
- Django backend
- PostgreSQL database
- backend nginx
- editor frontend
- planner frontend
- portal frontend
- root gateway nginx

## Files
- `scripts/` — Jenkins helper scripts
- `.env.example` — environment example for Jenkins-injected values

## Expected root entrypoints
- `Jenkinsfile`
- `docker-compose.yml`

## Jenkins behavior
1. prepare environment
2. backup database
3. test backend
4. test/build frontends through root docker compose
5. deploy full stack

Use the scripts in `deployment/jenkins/scripts/` from the root `Jenkinsfile`.
