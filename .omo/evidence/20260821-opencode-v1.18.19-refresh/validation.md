# OpenCode v1.18.19 refresh validation

Timestamp: 2026-08-21 03:22:34 CST

## Merge state

- Target branch: `ops/opencode-v1.18.19-20260821`
- Merge command: `git merge --no-commit --no-ff v1.18.19`
- Unmerged paths: 0
- `git diff --check`: pass
- YAML parse: pass for `.github/actions/setup-bun/action.yml` and `.github/workflows/test.yml`

## Focused validation

- `packages/opencode`: `bun test test/cli/tui/thread.test.ts` — 11 pass, 0 fail.
- `packages/opencode`: `bun test test/project/project.test.ts test/project/worktree-remove.test.ts test/util/filesystem.test.ts test/file/path-traversal.test.ts` — 98 pass, 1 platform-conditional skip, 0 fail.
- `packages/opencode`: `bun typecheck` — pass.
- `packages/tui`: `bun typecheck` — pass.
- `packages/app`: `bun typecheck && bun typecheck:e2e` — pass.
- `packages/opencode`: `bun run --conditions=browser ./src/index.ts --variant high --help` — pass; default TUI help exposes `--variant`.
- Root: `bun run script/build.ts --single --skip-install` — pass; produced the macOS arm64 carrier bundle.
- Built preview binary: 143,727,458 bytes, SHA-256 `7e772ec5784e5a79fe3dcb7cd0c9dfcd1092493e2c0b83706ed0640535f0883e`.
- PR Linux unit follow-up: the upstream help snapshot still asserted that top-level help must omit `--variant`; the assertion now matches the intentional startup flag. The help snapshot plus the full run-process regression file pass together: 14 pass, 0 fail, 34 snapshots.
- The same Linux run also exceeded an existing 15-second subprocess timing assertion by 346 ms under concurrent CI load; an immediate local rerun completed the target case in 9.61 seconds, so no product timeout behavior was changed.

## Scope note

Dependency installation was confined to this isolated worktree. Its repository lifecycle hook attempted to materialize a sibling worktree, so that subprocess was stopped before validation continued. No live carrier install or partner restart was performed during this validation stage.
