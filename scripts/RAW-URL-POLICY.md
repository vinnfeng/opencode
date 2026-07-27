# RAW-URL-POLICY

> D4 重设：raw URL / 外部资源获取安全策略（10 条件必须同时满足）
>
> 来源：旧提交 `7eb435a7`（仅去 community-setup 的 raw URL 改本地运行）不 cherry-pick，
> 在 `migration/company-opencode-validated-20260725` 分支按本策略重新实现。
> 基线 `ad052574`。

## 适用范围

`scripts/setup.sh` / `scripts/setup.ps1` / `scripts/community-setup.sh` / `scripts/community-setup.ps1`
中所有**从远程获取执行输入或二进制资产**的行为：脚本自身分发 URL（raw URL）、release 二进制下载、
配置仓库 clone/checkout。

## 10 条件（必须同时满足）

| # | 条件 | 实现 |
|---|------|------|
| 1 | 来源属 vinnfeng 自有 fork / 正式公司仓 / 明确批准官方上游 | `RELEASE_REPO=vinnfeng/opencode`、`CONFIG_REPO=vinnfeng/opencode-config` 均为 vinnfeng 自有 fork |
| 2 | URL 固定完整 commit SHA / 不可变 release 资产 / 带版本正式 tag | raw URL 固定到 `$RELEASE_TAG`（v1.3.17-kaiqu.5-d4-20260727 正式 tag）；release 资产走 `releases/download/$RELEASE_TAG`；CONFIG clone 后 checkout 固定 commit SHA（`CONFIG_REF`） |
| 3 | 不允许浮动 main/dev/latest 作执行输入 | 禁用 `release/kaiqu` 浮动分支；禁用 `git checkout main/office-windows/community` 浮动分支，改 checkout `$CONFIG_REF` 固定 SHA |
| 4 | 下载后验证 SHA256 或发布签名 | 下载二进制后取 `$DOWNLOAD_URL.sha256`，计算实际 SHA256 对比；不存在或不匹配立即阻断 |
| 5 | 脚本执行前保存来源/版本/哈希/获取时间 | 写入 `$MANIFEST_FILE`（source_url / version / sha256 / fetch_time），下载前/后落盘 |
| 6 | 一键安装入口显示真实来源与固定版本 | 完成 banner 显示来源 URL + 版本 tag + SHA256 摘要 |
| 7 | 来源/哈希/版本不一致立即阻断 | 运行时对比 `$MANIFEST_FILE` 记录与当前 `$DOWNLOAD_URL`/`$RELEASE_TAG`，不一致 err 阻断 |
| 8 | 不得把密钥 Token 认证参数拼入 URL | URL 仅 host/path，密钥走 `$KEYS_FILE`（0600，不进 git），不拼 query |
| 9 | 外部未知仓 / 短链接 / 动态跳转继续禁止 | 仅允许 `github.com/vinnfeng/*`，无短链/重定向/第三方仓 |
| 10 | 回滚资产必须事先存在 | rollback 前检查 `$BACKUP_DIR/opencode-<tag>` 存在（`[ -f ]` / `Test-Path`），不存在 err；更新前备份旧二进制 + manifest |

## 当前 gap（已知，非策略缺陷）

`v1.3.17-kaiqu.5-d4-20260727` release **未附 `.sha256` 资产**（HTTP 404 确认）。条件 4 机制就位：
`.sha256` 存在则验证，不存在则 `err` 阻断，强制 release 构建补 sha256 资产后方可安装。
这是策略约束（条件 4/7 的强制保障），非脚本 bug。

## 与 ad052574 基线差异

基线 `ad052574` 的 setup 脚本：
- raw URL 用 `release/kaiqu` 浮动分支（违反条件 2/3）
- 下载二进制无 SHA256 验证（违反条件 4）
- 无 manifest（违反条件 5）
- CONFIG checkout `main`/`office-windows`/`community` 浮动分支（违反条件 2/3）
- 无一致性阻断（违反条件 7）

D4 全面重设上述 6 点，保留 RELEASE_TAG 固定 tag（条件 2 已满足）+ 回滚资产检查（条件 10 已满足）+ vinnfeng 自有仓（条件 1 已满足）。
