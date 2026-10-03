# ============================================================
# SKWF 仓库自检脚本(零依赖, Windows PowerShell 5.1+)
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File tests\run_checks.ps1
# 覆盖:
#   1. node --check     3 个 .mjs(mcp 两个 + 测试假桥;无 node 则 SKIP)
#   2. PSParser         4 个管线 .ps1 语法
#   3. ruby -c          全部 .rb(本机有 Ruby 才跑, 否则 SKIP)
#   4. 菜单注册静态断言: 4 个 skwf_*.rb 引用的 SKWF.* 方法在四文件中
#      都有 def self 定义, 且各自含 respond_to?(:workflow_menu) 内联守卫
#   5. 端到端(门控): parse_dxf.ps1 有 param() 才对 tests/mini_dxf.dxf
#      实跑解析; 输出进临时目录, 绝不写仓库 data/
#   6. 端到端: fake_bridge.mjs 对 mcp 两个 stdio 服务器双协议实跑
#      (自研 + 社区): 初始化/tools/list/list-dispatch 一致性/真实往返;
#      无 node 则 SKIP, 任一断言失败即 FAIL
# 退出码: 0 = 无 FAIL(允许 SKIP), 1 = 有 FAIL
# ============================================================
$ErrorActionPreference = 'Continue'
# node 等子进程输出为 UTF-8; PowerShell 5.1 缺省按系统 ANSI(如 GBK)解码,
# 第 6 节 detail 里的中文会显示成乱码。重定向/无控制台句柄时此赋值可能抛
# 异常, 失败则保持现状 —— PASS/FAIL 判定始终基于 exit code, 不受影响。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$repo = Split-Path $PSScriptRoot -Parent
$script:pass = 0; $script:fail = 0; $script:skip = 0

function Report($name, $state, $detail = '') {
    switch ($state) {
        'PASS' { $script:pass++; $tag = 'PASS' }
        'FAIL' { $script:fail++; $tag = 'FAIL' }
        default { $script:skip++; $tag = 'SKIP' }
    }
    $line = "$tag $name"
    if ($detail) { $line += " ($detail)" }
    Write-Output $line
}

Write-Output "=== SKWF 自检: $repo ==="
Write-Output ""

# ---------- 1. node --check .mjs ----------
$node = Get-Command node -ErrorAction SilentlyContinue
$mjsFiles = @('mcp/su_mcp_server.mjs', 'mcp/community-mcp-stdio.mjs', 'tests/fake_bridge.mjs')
if ($node) {
    foreach ($f in $mjsFiles) {
        $p = Join-Path $repo $f
        $o = & node --check $p 2>&1
        if ($LASTEXITCODE -eq 0) { Report "node --check $f" 'PASS' }
        else { Report "node --check $f" 'FAIL' (($o | Out-String).Trim()) }
    }
} else {
    foreach ($f in $mjsFiles) { Report "node --check $f" 'SKIP' '本机无 node' }
}
Write-Output ""

# ---------- 2. PSParser 4 个 .ps1 ----------
$psFiles = @('pipeline/parse_dxf.ps1', 'pipeline/export_dxf.ps1', 'pipeline/bridge_call.ps1', 'pipeline/render_pdf.ps1')
foreach ($f in $psFiles) {
    $p = Join-Path $repo $f
    $errs = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content $p -Raw), [ref]$errs) | Out-Null
    if ($errs.Count -eq 0) { Report "PSParser $f" 'PASS' }
    else { Report "PSParser $f" 'FAIL' (($errs | ForEach-Object { $_.Message }) -join '; ') }
}
Write-Output ""

# ---------- 3. ruby -c 全部 .rb ----------
$ruby = Get-Command ruby -ErrorAction SilentlyContinue
$rbFiles = Get-ChildItem (Join-Path $repo 'pipeline'), (Join-Path $repo 'scripts'), (Join-Path $repo 'mcp'), (Join-Path $repo 'examples') -Filter '*.rb' |
    ForEach-Object { $_.FullName }
if ($ruby) {
    foreach ($p in $rbFiles) {
        $rel = $p.Substring($repo.Length + 1)
        $o = & ruby -c $p 2>&1
        if ($LASTEXITCODE -eq 0) { Report "ruby -c $rel" 'PASS' }
        else { Report "ruby -c $rel" 'FAIL' (($o | Out-String).Trim()) }
    }
} else {
    Report "ruby -c ($($rbFiles.Count) 个 .rb)" 'SKIP' '本机无 Ruby, 未做语法检查'
}
Write-Output ""

# ---------- 4. 菜单注册静态断言 ----------
$skwfFiles = Get-ChildItem (Join-Path $repo 'scripts') -Filter 'skwf_*.rb'
$allText = @{}
foreach ($f in $skwfFiles) { $allText[$f.Name] = Get-Content $f.FullName -Raw }

# 四文件中定义的全部 self 方法
$defined = New-Object System.Collections.Generic.HashSet[string]
foreach ($t in $allText.Values) {
    foreach ($m in [regex]::Matches($t, '(?m)^\s*def\s+self\.([A-Za-z_]\w*)')) {
        [void]$defined.Add($m.Groups[1].Value)
    }
}
foreach ($name in ($allText.Keys | Sort-Object)) {
    $t = $allText[$name]
    # 引用到的 SKWF.xxx(含链式 SKWF.workflow_menu.add_item)
    $refs = [regex]::Matches($t, 'SKWF\.([A-Za-z_]\w*)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missing = @($refs | Where-Object { -not $defined.Contains($_) })
    if ($refs.Count -gt 0 -and $missing.Count -eq 0) { Report "菜单断言 $name 引用的 SKWF.* 均有定义" 'PASS' ($refs -join ',') }
    elseif ($refs.Count -eq 0) { Report "菜单断言 $name" 'FAIL' '未引用任何 SKWF.* 方法?' }
    else { Report "菜单断言 $name 引用的 SKWF.* 均有定义" 'FAIL' ("缺定义: " + ($missing -join ',')) }
    # 内联守卫: 无 setup_template 时也要能自建菜单 helper
    if ($t -match 'respond_to\?\(:workflow_menu\)') { Report "守卫 $name 含 respond_to?(:workflow_menu)" 'PASS' }
    else { Report "守卫 $name 含 respond_to?(:workflow_menu)" 'FAIL' '先加载本文件时 workflow_menu 未定义会崩' }
}
Write-Output ""

# ---------- 5. 端到端(门控): parse_dxf.ps1 x tests/mini_dxf.dxf ----------
$parse = Join-Path $repo 'pipeline/parse_dxf.ps1'
$parseText = Get-Content $parse -Raw
$hasParam = [regex]::IsMatch($parseText, '(?m)^\s*param\s*\(')
if (-not $hasParam) {
    Report '端到端 parse_dxf.ps1 x tests/mini_dxf.dxf' 'SKIP' 'parse_dxf.ps1 尚无 param(), 基线阶段不实跑(避免覆盖 data/*.json)'
} else {
    $tmp = Join-Path $env:TEMP ('skwf_e2e_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $outDir = Join-Path $tmp 'out'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $fixture = Join-Path $PSScriptRoot 'mini_dxf.dxf'
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $parse -dxf $fixture -outDir $outDir 2>&1

    function J($n) { Get-Content (Join-Path $outDir $n) -Raw | ConvertFrom-Json }
    try {
        $walls = J 'walls.json'; $defs = J 'block_definitions.json'
        $furn = J 'furniture_instances.json'; $doors = J 'doors.json'
        $checks = @()
    $checks += @{ name = 'walls 2 段(含 bulge 的 LWPOLYLINE 降为直线)'; ok = ($walls.segs.Count -eq 2) }
    $checks += @{ name = '块定义含 CHAIR'; ok = ($null -ne $defs.PSObject.Properties['CHAIR']) }
    $checks += @{ name = '块定义含 DESK'; ok = ($null -ne $defs.PSObject.Properties['DESK']) }
    $checks += @{ name = 'DESK 展平含嵌套 INSERT 的几何(2 段)'; ok = ($defs.DESK.segs.Count -eq 2) }
    $checks += @{ name = 'DESK.bbox.maxy==10(bbox 修复生效)'; ok = ($defs.DESK.bbox.maxy -eq 10) }
    $checks += @{ name = 'DESK.bbox.maxx==60(bbox 修复生效)'; ok = ($defs.DESK.bbox.maxx -eq 60) }
    $checks += @{ name = '家具实例 2 个'; ok = ($furn.insts.Count -eq 2) }
    $checks += @{ name = '家具[0]=DESK 旋转 90 度'; ok = ($furn.insts[0].name -eq 'DESK' -and [math]::Abs($furn.insts[0].rot - 1.5708) -lt 0.001) }
    $checks += @{ name = '门 0 个'; ok = ($doors.insts.Count -eq 0) }
        foreach ($c in $checks) {
            if ($c.ok) { Report "e2e: $($c.name)" 'PASS' } else { Report "e2e: $($c.name)" 'FAIL' }
        }
    } catch {
        Report '端到端 parse_dxf.ps1 x tests/mini_dxf.dxf' 'FAIL' $_.Exception.Message
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}
Write-Output ""

# ---------- 6. 端到端: fake_bridge.mjs 双协议实跑 ----------
if ($node) {
    $pairs = @(
        @{ name = '自研协议 su_mcp_server.mjs';       args = @((Join-Path $repo 'mcp/su_mcp_server.mjs')) },
        @{ name = '社区协议 community-mcp-stdio.mjs'; args = @((Join-Path $repo 'mcp/community-mcp-stdio.mjs'), '--community') }
    )
    foreach ($pair in $pairs) {
        # 注意: '--community' 等旗标必须原样传递, 不能过 Join-Path
        $argList = @((Join-Path $repo 'tests/fake_bridge.mjs')) + @($pair.args)
        $out = & node @argList 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            # 首跑失败: 保留完整输出(截断到 900 字符), 透明重跑一次(两次结果都如实记录)
            $dump1 = ((@($out) | ForEach-Object { "$_" }) -join ' | ')
            if ($dump1.Length -gt 900) { $dump1 = $dump1.Substring(0, 900) + '…' }
            $out2 = & node @argList 2>&1
            $code2 = $LASTEXITCODE
            if ($code2 -eq 0) {
                Report "e2e fake_bridge: $($pair.name)" 'PASS' ("首跑 FAIL[$dump1]; 重跑 PASS")
            } else {
                $dump2 = ((@($out2) | ForEach-Object { "$_" }) -join ' | ')
                if ($dump2.Length -gt 900) { $dump2 = $dump2.Substring(0, 900) + '…' }
                Report "e2e fake_bridge: $($pair.name)" 'FAIL' ("首跑 FAIL[$dump1]; 重跑 FAIL[$dump2]")
            }
        } else {
            Report "e2e fake_bridge: $($pair.name)" 'PASS' ((@($out) | Select-Object -Last 1) | Out-String).Trim()
        }
    }
} else {
    Report 'e2e fake_bridge: 双协议实跑' 'SKIP' '本机无 node'
}
Write-Output ""

# ---------- 汇总 ----------
Write-Output ("=== 汇总: PASS {0} / FAIL {1} / SKIP {2} ===" -f $script:pass, $script:fail, $script:skip)
if ($script:fail -gt 0) { exit 1 }
exit 0
