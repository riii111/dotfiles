# Comprehensive Next.js Code Check

Perform a full Next.js/Frontend code quality check for the current project.
If a frontend/ folder exists under root, move to it before executing.

1. Run biome check . for linting and formatting verification
2. Execute yarn build to check for build errors and type issues
3. Run yarn test if test scripts exist
4. Analyze bundle size with next-bundle-analyzer if configured
5. Check for accessibility issues if applicable

For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
