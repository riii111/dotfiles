# Comprehensive Rust Code Check

Perform a full Rust code quality check for the current project.
If a backend/ folder exists under root, move to it before executing.

1. Run cargo fmt to check formatting
2. Execute cargo clippy -- -D warnings for linting
3. Run "source ~/.env && cargo nextest run --workspace" for all tests
4. Execute cargo audit for security vulnerabilities

For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially. 
