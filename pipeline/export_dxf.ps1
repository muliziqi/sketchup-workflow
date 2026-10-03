param(
    [string]$dwg = '',
    [string]$dxf = ''
)
$ErrorActionPreference = 'Stop'

# ---- 路径三级回退: 脚本所在目录(仓库根) -> $env:SKWF_HOME -> 用户目录 ----
if ($PSScriptRoot)      { $skwfRoot = Split-Path $PSScriptRoot -Parent }
elseif ($env:SKWF_HOME) { $skwfRoot = $env:SKWF_HOME }
else                    { $skwfRoot = Join-Path $HOME 'sketchup-workflow' }

# 输入 DWG 缺省: 仓库根\floor_plan.dwg -> AutoCAD 自带样例 Floor Plan Sample.dwg
if (-not $dwg) {
    $cand = @()
    $own = Join-Path $skwfRoot 'floor_plan.dwg'
    if (Test-Path $own) { $cand += $own }
    $sample = Get-ChildItem -Path (Join-Path $env:ProgramFiles 'Autodesk') -Recurse -Filter 'Floor Plan Sample.dwg' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($sample) { $cand += $sample.FullName }
    if ($cand.Count -eq 0) {
        Write-Output "ERROR: 未指定输入 DWG。用法: export_dxf.ps1 -dwg <图纸.dwg> [-dxf <输出.dxf>]"
        Write-Output "(缺省按 仓库根\floor_plan.dwg -> AutoCAD 样例图 查找; 可用 SKWF_HOME 指定工作根)"
        exit 1
    }
    $dwg = $cand[0]
}
# 输出 DXF 缺省: 仓库根\floor_plan.dxf(parse_dxf.ps1 的缺省输入即此路径)
if (-not $dxf) { $dxf = Join-Path $skwfRoot 'floor_plan.dxf' }
$dxfDir = Split-Path $dxf -Parent
if ([string]::IsNullOrEmpty($dxfDir)) { $dxfDir = (Get-Location).Path }
if (-not (Test-Path $dxfDir)) { New-Item -ItemType Directory -Force -Path $dxfDir | Out-Null }
if (Test-Path $dxf) { Remove-Item $dxf -Force }

# 记录 AutoCAD 实例来源: 复用已开实例时绝不 Quit(那是用户自己开的)
$launchedInstance = $false
try {
    try {
        $acad = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application')
        Write-Output "reusing running AutoCAD"
    } catch {
        $acad = New-Object -ComObject AutoCAD.Application
        $launchedInstance = $true
        Write-Output "launched new AutoCAD"
    }
} catch {
    Write-Output "ERROR: 无法连接/启动 AutoCAD(COM) —— 请确认本机已安装 AutoCAD 桌面版;"
    Write-Output "或先手动打开 AutoCAD 再重跑本脚本。"
    Write-Output ("原始错误: " + $_.Exception.Message)
    exit 1
}

try {
    $acad.Visible = $true
    $doc = $acad.Documents.Open($dwg, $true)
} catch {
    Write-Output "ERROR: AutoCAD 打不开图纸: $dwg"
    Write-Output "可能原因: 文件不存在 / 被其他程序占用 / 版本过高 / 需要恢复; 可先在 AutoCAD 里手动打开确认。"
    Write-Output ("原始错误: " + $_.Exception.Message)
    if ($launchedInstance) { try { $acad.Quit() } catch {} }
    exit 1
}
Write-Output "document opened"

try {
    $doc.SetVariable('FILEDIA', 0) | Out-Null
    # path + precision 16 + Enter, then Enter on the format prompt (default = 2018 DXF)
    $doc.SendCommand('._DXFOUT "' + $dxf + '" 16' + [char]10 + [char]10)
} catch {
    Write-Output "ERROR: DXFOUT 命令发送失败 —— 图纸可能处于锁定或有挂起命令, 先在 AutoCAD 里按 Esc 取消挂起命令后重试。"
    Write-Output ("原始错误: " + $_.Exception.Message)
    try { $doc.SetVariable('FILEDIA', 1) | Out-Null } catch {}
    try { $doc.Close($false) } catch {}
    if ($launchedInstance) { try { $acad.Quit() } catch {} }
    exit 1
}

$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline -and -not (Test-Path $dxf)) { Start-Sleep -Milliseconds 800 }
Start-Sleep -Seconds 2

if (Test-Path $dxf) {
    $len = (Get-Item $dxf).Length
    Write-Output ("DXF written: " + $len + " bytes")
    $head = [System.IO.File]::ReadAllLines($dxf)[0..1] -join '/'
    Write-Output ("header: " + $head)
} else {
    Write-Output "DXF EXPORT FAILED"
}

try { $doc.SetVariable('FILEDIA', 1) | Out-Null } catch {}
try { $doc.Close($false) } catch { Write-Output ("WARN: 关闭文档失败(可能已被手动关闭): " + $_.Exception.Message) }
if ($launchedInstance) {
    $acad.Quit()
} else {
    Write-Output "AutoCAD was already running; left it open"
}
Write-Output "DONE"
