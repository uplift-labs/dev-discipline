### Development discipline (dev-discipline)
- Commit after every meaningful milestone (new function, bug fix, refactor complete) because uncommitted work is easy to lose. Enforced by `rare-commits-reminder`.
- Use conventional commit format: `type(scope): description`. Types: feat, fix, chore, docs, style, refactor, perf, test, ci, build, revert. Enforced by `commit-checks`.
- Write tests before implementation when possible. `tdd-order` will remind you if you edit code before tests.
- Run the full test suite before pushing to main. If `.uplift/dev-discipline/test-cmd` is configured, `regression-guard` will run it automatically and block on failures.
