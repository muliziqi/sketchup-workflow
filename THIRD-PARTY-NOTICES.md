# 第三方组件声明(THIRD-PARTY NOTICES)

登记本仓库所含第三方代码的来源与核实状态。本文件只是来源登记,不构成许可授予;
整个仓库的许可证选型由仓库主人决定(仓库当前未附带 LICENSE 文件)。

## mcp/community-plugin-main.rb

| 项 | 说明 |
|---|---|
| 来源 | [mhyrr/sketchup-mcp](https://github.com/mhyrr/sketchup-mcp) 的 SketchUp 插件主文件(引入时的上游版本) |
| 本地文件 | `mcp/community-plugin-main.rb`(1859 行,65,899 字节) |
| 本地校验 | git blob SHA-1:`90117b4ff5412a3636a0fb2cdebb948f02ad0d4a`——2026-10-01 经 api.github.com 核实,与上游 main 树 `su_mcp/su_mcp/main.rb` 的 blob **完全一致**(本地 65,899 字节为 CRLF 行尾,上游 blob 64,040 字节为 LF,差 1,859 恰等于行数);SHA-256:`8d200e9cf0834d3101c93a55b09c86f87b912f58222cbb5b3fa3e5370e05e5df` |
| 上游许可 | 上游 README 末节声明 "License: MIT"(2026-10-01 经 raw.githubusercontent.com 核实原文);**但上游 main 树无 LICENSE 文件**(递归列表 truncated:false,GitHub API 的 license 字段亦为 null)——即上游仅以 README 一句话声明 MIT,许可文本与版权行缺失,授权链条未完全闭环 |
| 待办 | **商用分发前须由仓库主人确认**(本文件只登记事实,不代替决策):取得上游 LICENSE 原文或与上游作者确认后,决定 ①保留并合入 NOTICE(附 MIT 版权声明与许可全文) ②重写替换 ③从交付包剔除 |

核实命令(本机可复现):

```powershell
git hash-object mcp/community-plugin-main.rb
# -> 90117b4ff5412a3636a0fb2cdebb948f02ad0d4a(与上游 su_mcp/su_mcp/main.rb blob 一致)
Get-FileHash -Algorithm SHA256 mcp/community-plugin-main.rb
```

上游核实记录(2026-10-01;本机 WebFetch 因 TLS 拦截不可用,经 web_reader 访问 api.github.com 与 raw.githubusercontent.com 完成):

- `api.github.com/repos/mhyrr/sketchup-mcp` → `"license": null`(GitHub 未检出许可文件)
- `api.github.com/repos/mhyrr/sketchup-mcp/git/trees/main?recursive=1` → 全树(truncated:false)无 LICENSE 文件;`su_mcp/su_mcp/main.rb` blob = `90117b4ff5412a3636a0fb2cdebb948f02ad0d4a`
- `raw.githubusercontent.com/mhyrr/sketchup-mcp/main/README.md` → 末节 "## License / MIT"

注意:origin 已是公开仓库,该文件内容对外可见;上述待办宜尽早处理。
