```markdown
# turbo-potato Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches the core development patterns and conventions used in the `turbo-potato` TypeScript codebase. It covers file naming, import/export style, commit message habits, and testing patterns. While no specific frameworks or automated workflows are detected, this guide will help you write consistent, maintainable code and understand how to contribute effectively.

## Coding Conventions

### File Naming
- Use **PascalCase** for all file names.
  - Example: `MyComponent.ts`, `UserService.ts`

### Import Style
- Use **relative imports** for referencing other modules.
  - Example:
    ```typescript
    import { UserService } from './UserService';
    ```

### Export Style
- Use **named exports** rather than default exports.
  - Example:
    ```typescript
    // In UserService.ts
    export function getUser(id: string) { ... }

    // In another file
    import { getUser } from './UserService';
    ```

### Commit Messages
- Commit messages are **freeform** and do not follow a strict prefix or type.
- Typical length: ~33 characters.
  - Example: `Add user authentication logic`

## Workflows

### Adding a New Module
**Trigger:** When you need to add a new feature or utility.
**Command:** `/add-module`

1. Create a new file using PascalCase (e.g., `NewFeature.ts`).
2. Implement your logic using named exports.
3. Use relative imports to include dependencies.
4. Write a corresponding test file (e.g., `NewFeature.test.ts`).
5. Commit your changes with a clear, concise message.

### Writing and Running Tests
**Trigger:** When you need to verify your code works as intended.
**Command:** `/run-tests`

1. Create a test file named with the pattern `*.test.*` (e.g., `MyComponent.test.ts`).
2. Write your test cases using your preferred testing framework.
3. Run the tests using your project's test runner (framework is unspecified; check project documentation or package.json).
4. Review test results and fix any failing cases.

## Testing Patterns

- Test files follow the `*.test.*` naming convention, such as `UserService.test.ts`.
- The specific testing framework is **unknown**; check the repository for more details.
- Place test files alongside the modules they test or in a dedicated test directory.

**Example Test File:**
```typescript
// UserService.test.ts
import { getUser } from './UserService';

describe('getUser', () => {
  it('returns user data for valid id', () => {
    // test implementation
  });
});
```

## Commands
| Command        | Purpose                                      |
|----------------|----------------------------------------------|
| /add-module    | Scaffold and add a new module or feature     |
| /run-tests     | Run all test files in the codebase           |
```
