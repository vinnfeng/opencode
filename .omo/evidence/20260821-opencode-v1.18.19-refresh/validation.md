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
- Built preview binary: 143,727,458 bytes, SHA-256 `6c7f58fb5a0a8ee8bcaa9cf376c6340bf0ec954b28b45f0be53e9495d7c58e21`.

## Scope note

Dependency installation was confined to this isolated worktree. Its repository lifecycle hook attempted to materialize a sibling worktree, so that subprocess was stopped before validation continued. No live carrier install or partner restart was performed during this validation stage.
