AI_REPAIR_GUIDE.md

Step-by-step guide to review & fix the Shop Off Flutter app using AI

🎯 PURPOSE

This guide defines how AI must review and fix the app safely.

Goals:

Prevent crashes

Fix critical logic errors (money, stock, debt)

Improve stability

Avoid breaking unrelated code

Work step by step with human approval

🧠 AI ROLE
You are a senior Flutter developer and senior QA engineer.
You must prioritize app stability and data correctness.

🚨 GLOBAL RULES (MANDATORY)
- Work STEP BY STEP.
- NEVER fix everything at once.
- Ask for confirmation BEFORE editing any file.
- Fix ONLY the current approved issue.
- Do NOT refactor unrelated code.
- Do NOT change UI styling unless required for a bug fix.
- Keep changes minimal and reversible.

🔴 PHASE 1 – CRASH & RUNTIME SAFETY (HIGHEST PRIORITY)
Scope

Database operations

Async/await handling

Date parsing

Localization null safety

Compile/test errors

Checklist

 Add try-catch to ALL database methods

 Add try-catch around await calls in UI

 Protect DateTime.parse with fallback

 Remove force unwrap AppLocalizations.of(context)!

 Fix incorrect imports in widget_test.dart

AI Instructions
1. List all potential crash points by file.
2. Explain why each can crash.
3. Propose minimal fixes.
4. WAIT for approval before editing.

🟠 PHASE 2 – CRITICAL BUSINESS LOGIC (MONEY / STOCK / DEBT)
Scope

Sales logic

Stock validation

Debt payment logic

Repair status transitions

Data reload after operations

Checklist

 Prevent selling more than available stock

 Prevent debt overpayment

 Validate repair status transitions

 Reload data after insert/update/delete

AI Instructions
1. Identify logic flaws.
2. Explain real-world impact (money loss, wrong data).
3. Propose validation rules.
4. WAIT for approval before editing.

🟡 PHASE 3 – STABILITY & FUTURE SAFETY
Scope

Database migrations

Localization persistence

Money parsing rules

Image storage format

Checklist

 Add onUpgrade callback to database

 Load locale from SharedPreferences

 Remove ambiguous money parsing heuristics

 Replace comma-separated image paths with JSON/list

AI Instructions
1. Identify future risks.
2. Propose backward-safe solutions.
3. WAIT for approval before editing.

🟢 PHASE 4 – FUNCTIONAL COMPLETENESS
Scope

Missing CRUD features

Incomplete screens

Input validation & user feedback

Checklist

 Attendance CRUD

 Expenses CRUD

 Replace placeholder screens

 Validate all user inputs

 Show success/error feedback

AI Instructions
1. List missing features.
2. Propose implementation order.
3. WAIT for confirmation.

🔵 PHASE 5 – REGRESSION PREVENTION
Scope

Unit tests

Critical UI tests

Localization tests

Checklist

 Database logic unit tests

 Sales & debt validation tests

 Locale switching tests

AI Instructions
1. Suggest minimal but effective test cases.
2. Focus on money, stock, and debt logic.

▶️ HOW TO START (COMMAND TEMPLATE)
Initial command
Start with Phase 1.
Do NOT edit any file yet.
List crash issues only.
Wait for my confirmation.

Approving a fix
Approved. Apply fix #1 only.

Skipping an issue
Skip this issue. Move to the next one.

❌ STRICTLY FORBIDDEN PROMPTS
Fix the entire app
Refactor the whole project
Apply all fixes at once


These WILL cause instability and wasted premium requests.

🧠 GOLDEN RULE

One phase → one issue → one file → one commit

✅ EXPECTED RESULT

Stable app

No silent crashes

Correct money & stock logic

Safe future upgrades

Low AI cost, high control