PR Title: chore: payroll lock, async-context fixes, UI deprecations & cleanup

Summary
-------
This PR collects the work done to improve repo health and fix a small feature:

- Feature: Add payroll-month locking (DB table + helpers + UI hooks)
- Fixes: Systematic fixes to "Don't use BuildContext across async gaps" (captured scaffold messenger / navigator before awaits and added mounted checks)
- Deprecations: Replaced `Color.withOpacity(...)` usage where needed (previous batches) and applied other minor deprecation fixes
- Cleanup: Applied `dart fix` automated fixes (unused imports, prefer_const, prefer_final, minor style fixes)

What I changed (high level)
---------------------------
- DB
  - `lib/data/db_helper.dart`: added `payroll_locks` table creation (onCreate & onUpgrade) and helper methods:
    - `isPayrollMonthLocked`, `setPayrollMonthLock`, `getPayrollLocks`

- Async-context fixes (examples)
  - `lib/views/sale_detail_view.dart` (`_printWifi`) — capture messenger before awaiting printer selection
  - `temp_order_list.dart` — capture `messenger`/`navigator` in delete dialog
  - `lib/views/qr_scan_view.dart` — capture messenger/navigator and use them across async flows
  - `lib/views/expense_view.dart` — capture navigator in save dialog; fixed dialog syntax
  - (many other files were adjusted in small batches) — see commit history for full file list

- Automated and minor cleanup
  - Ran `dart fix --apply` and fixed 131 issues automatically across ~48 files (unused imports, prefer_const, prefer_final, curly braces, etc.)

Tests & Analyzer
----------------
- Tests: All unit tests pass: `All tests passed!` (46 tests)
- Analyzer: Issues reduced from ~240 → ~102 after the work. Remaining items are mostly non-blocking unused imports/fields, deprecations, and a few TODOs:
  - Notable remaining issues: `lib/services/connectivity_service.dart` references `UserService` (undefined in that file), `enabled` named parameter errors in `parts_inventory_view.dart` and `payroll_view.dart` (API changes), and several `dead_code` findings.

Branch & PR
-----------
- Branch: `release/final-cleanup` (pushed)
- Create PR: https://github.com/itquanghuy85/quanlyshop/pull/new/release/final-cleanup

Notes & Follow-ups
------------------
- I kept changes small and focused per batch to make review easier (several small commits and pushes).
- Remaining analysis items require small, manual review and decisions (e.g., API changes, removing dead code). I recommend addressing those in a follow-up PR so this one stays reviewable.

Files changed (high level)
--------------------------
- Many UI views and widgets: `lib/views/*`, `lib/widgets/*` (async-context fixes + UI deprecation updates)
- DB helper: `lib/data/db_helper.dart` (payroll locking)
- Tests: `test/db_payroll_lock_test.dart` (added, passing)
- Automated fixes changed many files (unused imports / prefer_const / minor lints)

If you'd like, I can open the PR description as a GitHub PR (requires an authenticated API or the `gh` CLI), or you can open it using the branch link above.

---

Checklist
- [x] Async-context fixes (captured messengers/navigators / added mounted guards)
- [x] Automated cleanup (`dart fix` applied)
- [x] Tests run and pass (`flutter test`)
- [x] Analyzer re-run after each batch
- [x] Pushed changes and created PR branch

If you want a separate PR per feature (e.g., payroll feature vs cleanup), I can split the commits into feature branches and prepare separate PRs.
