# Playwright Test Creation and Execution

Create and execute Playwright tests based on the provided changes: $ARGUMENTS

Follow these steps:

1. **Plan the Test Scenario**
   - Analyze the implementation changes and requirements
   - Use the `/project:playwright-plan` command to create a detailed test scenario
   - Review the generated scenario for completeness

2. **Create Test Files**
   - Generate Playwright test files based on the scenario
   - Ensure proper test structure with describe/it blocks
   - Include appropriate selectors and assertions
   - Add error handling and retry logic where needed

3. **Prepare Test Environment**
   - Verify Playwright configuration exists
   - Check for required test data or fixtures
   - Ensure the development server is running if needed

4. **Execute Tests**
   - Run: `playwright test` for all tests
   - Or run specific test: `playwright test <test-file>` if specified
   - Capture test results and any failures

5. **Report Results**
   Your obligation is to "report the current status without deception. 
   It does not matter if it is an error or a success, report it to the user.
   - Display test execution summary
   - For failed tests, show:
     - Error messages and stack traces
     - Screenshot locations (if captured)
     - Video recordings (if enabled)
     - Suggested fixes for common issues

6. **Optional: Debug Mode**
   - If tests fail, offer to run in debug mode:
     - `playwright test --debug`
   - Provide guidance on using Playwright Inspector

Remember to commit the test files after successful execution.
