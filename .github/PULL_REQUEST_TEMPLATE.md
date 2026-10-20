## 改动说明

（这个 PR 修了什么 / 加了什么，一两句）

## 自查清单

- [ ] `python -m py_compile relay/workbuddy-openai-relay.py ui/wb_bridge_ui.py` 通过
- [ ] 改动的 `.ps1` 语法检查通过（CI 会跑）
- [ ] 没有提交 `config/settings.psd1` / `config/cordis.patch.current.yml` / `ui/dist`
- [ ] 没有提交任何 token、私钥、真实账号 UID
- [ ] 如果改了行为，同步更新了 README / CHANGELOG

## 测试方式

（在什么环境、怎么验证的，例如：本机 WorkBuddy 5.8.3，跑了一次完整启动 + 工具调用）