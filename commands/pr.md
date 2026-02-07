---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git branch:*), Bash(git log:*), Bash(gh pr:*)
description: Create a new Pull Request
argument-hint: [mode] [include-how-to-test]
---
# Create Pull Request

## Overview
Automate the creation of well-structured commits and pull requests by analyzing code changes and following established conventions.

## Context
- Current branch: !`git branch --show-current`
- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Recent commits: !`git log --oneline -10`

## Process

### 0. Get existing PRs
- Use command `gh pr list --state all --json number,title,headRefName --head <CURRENT_BRANCH>` to list exising PRs and add them to context

### 1. Commit changes
- **Run /commit** to create structured commits for the current branch

### 3. Generate Pull Request
- **Title**: Brief conventional commit message about the changes
- **Description structure**:
  
  **Context:**
  - Brief explanation of what was changed and why
  - Link any related issues or requirements
  - Highlight any breaking changes or important considerations
  
  **How to Test:** *(should be included: $2)*
  - Specific steps to verify the changes work correctly
  - Any setup requirements or test data needed
  - Expected behavior after the changes

- **Instructions**: 
  - show me the PR content before creating the PR
  - generate the PR in $1 mode
  - always consider `main` as the parent branch. compare changes from the current branch with the `main` branch

### 4. Open Generated PR
- Run `gh pr view -w` to open the created PR on the browser

## Best Practices
- **Keep commits atomic**: Each commit should represent one logical change
- **Write for reviewers**: Assume they need context about the changes
- **Be specific**: Avoid vague descriptions like "fix bugs" or "update code"
- **Reference issues**: Link to tickets, requirements, or discussions when relevant
- **Update existing PRs**: If a PR already exists, update it with new relevant information

## Example Outputs

**Commit Messages:**

feat(workflow): implement parallel step execution
fix(api): resolve race condition in task processing  
docs(application): update component usage examples

**PR Description:**

## Context
Implements parallel execution for workflow steps to improve performance. Previously, steps executed sequentially even when they had no dependencies, causing unnecessary delays in workflow completion.

## How to Test
1. Create a workflow with multiple independent steps
2. Run the workflow and observe execution time
3. Verify all steps complete successfully and results are correct
4. Check workflow logs show parallel execution indicators
