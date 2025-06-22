# Full Stack Code Quality Check

Perform comprehensive code quality checks for both backend (Rust) and frontend (Next.js) simultaneously.

Execute the following in parallel:

## Backend (if backend/ exists):
1. Navigate to backend/ and run:
   - cargo clippy -- -D warnings  
   - source .env && cargo nextest run --workspace
   - cargo audit

## Frontend (if frontend/ exists):
1. Navigate to frontend/ and run:
   - biome check .
   - yarn build

## Parallel Execution Strategy:
- Use background processes (&) or GNU parallel for simultaneous execution
- Capture output from each process
- Wait for all processes to complete
- Provide a consolidated report showing:
  - ✅ Passed checks
  - ❌ Failed checks with error details
  - ⏱️ Execution time for each check
  - 📊 Overall status summary

For maximum efficiency, start all checks simultaneously and collect results as they complete.
Example approach:
```bash
# Start all checks in parallel
(cd backend && cargo fmt --check) &
(cd backend && cargo clippy -- -D warnings) &
(cd backend && source ~/.env && cargo nextest run --workspace) &
(cd backend && cargo audit) &
(cd frontend && biome check .) &
(cd frontend && yarn build) &
(cd frontend && yarn test) &

# Wait for all background jobs
wait

# Collect and report results
