param(
    [string]$dxf = '',
    [string]$outDir = ''
)
$ErrorActionPreference = 'Continue'

# ---- 路径三级回退: 脚本所在目录(仓库根) -> $env:SKWF_HOME -> 用户目录 ----
# 控制台直接粘贴/点开运行时 $PSScriptRoot 为空, 不能只依赖它
if ($PSScriptRoot)      { $skwfRoot = Split-Path $PSScriptRoot -Parent }
elseif ($env:SKWF_HOME) { $skwfRoot = $env:SKWF_HOME }
else                    { $skwfRoot = Join-Path $HOME 'sketchup-workflow' }

if (-not $dxf) {
    $cand = @((Join-Path $skwfRoot 'floor_plan.dxf'), (Join-Path $skwfRoot 'data\floor_plan.dxf'))
    $dxf = $cand | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $dxf) {
        Write-Output "ERROR: 未指定输入 DXF。用法: parse_dxf.ps1 -dxf <图纸.dxf> [-outDir <输出目录>]"
        Write-Output "(缺省按 仓库根\floor_plan.dxf -> 仓库根\data\floor_plan.dxf 查找; 可用 SKWF_HOME 指定工作根)"
        exit 1
    }
}
if (-not $outDir) { $outDir = Join-Path $skwfRoot 'data' }
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$walls  = New-Object System.Collections.Generic.List[object]
$shelv  = New-Object System.Collections.Generic.List[object]
$glaz   = New-Object System.Collections.Generic.List[object]
$cols   = New-Object System.Collections.Generic.List[object]
$stairs = New-Object System.Collections.Generic.List[object]
$grids  = New-Object System.Collections.Generic.List[object]
$panels = New-Object System.Collections.Generic.List[object]
$doors  = New-Object System.Collections.Generic.List[object]
$furnInsts = New-Object System.Collections.Generic.List[object]
$labels = New-Object System.Collections.Generic.List[object]

$doorLayer = 'E-F-DOOR'
$doorNames = @('DOOR','DR-36','DR-72P','DR-69P')
$wallLayers  = @('E-B-FURR','E-B-CORE','IWALLE','E-B-ELEV')
$glazLayers  = @('E-B-GLAZ','E-B-MULL','E-F-SILL')
$labelLayers = @('EMPLOYEE','ROOMNAME','ROOM-NUM','PRINTER_ISLAND')

$rawDefs = @{}   # name -> @{base=[x,y]; segs=List; polys=List; ins=List}

function New-Seg([string]$layer, [double]$x1, [double]$y1, [double]$x2, [double]$y2) {
    @{ layer = $layer; x1 = [math]::Round($x1,3); y1 = [math]::Round($y1,3); x2 = [math]::Round($x2,3); y2 = [math]::Round($y2,3) }
}
function New-DefSeg([double]$x1, [double]$y1, [double]$x2, [double]$y2) {
    @{ x1 = [math]::Round($x1,3); y1 = [math]::Round($y1,3); x2 = [math]::Round($x2,3); y2 = [math]::Round($y2,3) }
}

function Route-Line([string]$layer, [double]$x1, [double]$y1, [double]$x2, [double]$y2) {
    if ($layer -in $wallLayers) { $script:walls.Add((New-Seg $layer $x1 $y1 $x2 $y2)) | Out-Null }
    elseif ($layer -eq 'E-B-SHEL') { $script:shelv.Add((New-Seg $layer $x1 $y1 $x2 $y2)) | Out-Null }
    elseif ($layer -in $glazLayers) { $script:glaz.Add((New-Seg $layer $x1 $y1 $x2 $y2)) | Out-Null }
    elseif ($layer -eq 'E-S-COLM') { $script:cols.Add((New-Seg $layer $x1 $y1 $x2 $y2)) | Out-Null }
    elseif ($layer -eq 'E-F-STAIR') { $script:stairs.Add((New-Seg $layer $x1 $y1 $x2 $y2)) | Out-Null }
    elseif ($layer -eq 'GRIDLN') { $script:grids.Add((New-Seg $layer $x1 $y1 $x2 $y2)) | Out-Null }
    elseif ($layer -eq 'PANELS_201') {
        $script:panels.Add(@{ layer = $layer; closed = $false; pts = @(@([math]::Round($x1,3),[math]::Round($y1,3)), @([math]::Round($x2,3),[math]::Round($y2,3))) }) | Out-Null
    }
}
function Route-Poly([string]$layer, [bool]$closed, $pts) {
    if ($layer -eq 'PANELS_201') {
        $script:panels.Add(@{ layer = $layer; closed = $closed; pts = $pts }) | Out-Null
        return
    }
    $n = $pts.Count
    if ($n -lt 2) { return }
    $pp = $pts
    if ($closed) { $all = New-Object System.Collections.Generic.List[object]; foreach ($p in $pp) { $all.Add($p) | Out-Null }; $all.Add($pp[0]) | Out-Null; $pp = $all }
    for ($i = 0; $i -lt $pp.Count - 1; $i++) {
        Route-Line $layer $pp[$i][0] $pp[$i][1] $pp[$i+1][0] $pp[$i+1][1]
    }
}

$lines = [System.IO.File]::ReadAllLines($dxf)
Write-Output ("lines: " + $lines.Count)

$section = ''
$cur = $null          # current entity dict
$curDef = $null       # current raw def
$poly = $null         # active old-style POLYLINE accumulator
$inDefCtx = $false
$unknownTypes = @{}   # 未解析几何的图元类型计数(type -> 数量), 见 Flush-Entity 末尾

function Flush-Entity($e) {
    if ($e -eq $null) { return }
    $t = $e['type']
    # old-style polyline vertex / terminator
    if ($t -eq 'VERTEX' -and $script:poly -ne $null) {
        if ($e.ContainsKey('10')) { $script:poly.pts.Add(@([math]::Round([double]$e['10'],3), [math]::Round([double]$e['20'],3))) | Out-Null }
        return
    }
    if ($t -eq 'SEQEND' -and $script:poly -ne $null) {
        $pl = $script:poly; $script:poly = $null
        if ($pl.pts.Count -ge 2) {
            if ($script:inDefCtx) { $script:curDef.polys.Add(@{ closed = $pl.closed; pts = $pl.pts }) | Out-Null }
            else { Route-Poly $pl.layer $pl.closed $pl.pts }
        }
        return
    }
    $layer = if ($e.ContainsKey('8')) { $e['8'] } else { '0' }

    if ($t -eq 'LINE') {
        if ($e.ContainsKey('10') -and $e.ContainsKey('11')) {
            if ($script:inDefCtx) { $script:curDef.segs.Add((New-DefSeg ([double]$e['10']) ([double]$e['20']) ([double]$e['11']) ([double]$e['21']))) | Out-Null }
            else { Route-Line $layer ([double]$e['10']) ([double]$e['20']) ([double]$e['11']) ([double]$e['21']) }
        }
        return
    }
    if ($t -eq 'LWPOLYLINE') {
        $pts = $e['pts']
        if ($pts -ne $null -and $pts.Count -ge 2) {
            $closed = ([int]$e['70'] -band 1) -eq 1
            if ($script:inDefCtx) { $script:curDef.polys.Add(@{ closed = $closed; pts = $pts }) | Out-Null }
            else { Route-Poly $layer $closed $pts }
        }
        return
    }
    if ($t -eq 'POLYLINE') {
        $script:poly = @{ closed = (([int]$e['70'] -band 1) -eq 1); pts = (New-Object System.Collections.Generic.List[object]); layer = $layer }
        return
    }
    if ($t -eq 'ARC') {
        $c = [double]$e['10']; $d = [double]$e['20']; $r = [double]$e['40']
        $a0 = [double]$e['50'] * [math]::PI / 180.0; $a1 = [double]$e['51'] * [math]::PI / 180.0
        if ($a1 -lt $a0) { $a1 += 2*[math]::PI }
        $pts = @()
        for ($k = 0; $k -le 16; $k++) {
            $a = $a0 + ($a1-$a0)*$k/16
            $pts += ,@([math]::Round($c+$r*[math]::Cos($a),3), [math]::Round($d+$r*[math]::Sin($a),3))
        }
        if ($script:inDefCtx) { $script:curDef.polys.Add(@{ closed = $false; pts = $pts }) | Out-Null }
        else { Route-Poly $layer $false $pts }
        return
    }
    if ($t -eq 'CIRCLE') {
        $c = [double]$e['10']; $d = [double]$e['20']; $r = [double]$e['40']
        $pts = @()
        for ($k = 0; $k -le 24; $k++) {
            $a = 2*[math]::PI*$k/24
            $pts += ,@([math]::Round($c+$r*[math]::Cos($a),3), [math]::Round($d+$r*[math]::Sin($a),3))
        }
        if ($script:inDefCtx) { $script:curDef.polys.Add(@{ closed = $true; pts = $pts }) | Out-Null }
        else { Route-Poly $layer $true $pts }
        return
    }
    if ($t -eq 'INSERT') {
        $nm = if ($e.ContainsKey('2')) { $e['2'] } else { '' }
        $x = [double]$e['10']; $y = [double]$e['20']
        $rot = 0.0; if ($e.ContainsKey('50')) { $rot = [double]$e['50'] * [math]::PI / 180.0 }
        $sx = 1.0; if ($e.ContainsKey('41')) { $sx = [double]$e['41'] }
        $sy = 1.0; if ($e.ContainsKey('42')) { $sy = [double]$e['42'] }
        if ($script:inDefCtx) {
            if ($nm -ne '' -and -not $nm.StartsWith('*')) {
                $script:curDef.ins.Add(@{ name = $nm; x = $x; y = $y; rot = $rot; sx = $sx; sy = $sy }) | Out-Null
            }
            return
        }
        if ($nm -eq 'RMNUM' -or $nm -eq '' -or $nm.StartsWith('*')) { return }
        $rec = @{ name = $nm; x = [math]::Round($x,3); y = [math]::Round($y,3); rot = [math]::Round($rot,4); sx = $sx; sy = $sy; layer = $layer }
        if ($layer -eq $doorLayer -or $nm -in $doorNames) { $script:doors.Add($rec) | Out-Null }
        else { $script:furnInsts.Add($rec) | Out-Null }
        return
    }
    if ($t -in @('MTEXT','TEXT')) {
        if (-not ($layer -in $labelLayers)) { return }
        $txt = ''
        if ($e.ContainsKey('3')) { foreach ($c3 in $e['3']) { $txt += $c3 } }
        if ($e.ContainsKey('1')) { $txt += $e['1'] }
        $txt = $txt -replace '\\[A-Za-z][^;|}]*;?', '' -replace '[{}]', '' -replace '\\P', ' ' -replace '\\~', ' '
        $txt = $txt.Trim()
        if ($txt -ne '') {
            $script:labels.Add(@{ x = [math]::Round([double]$e['10'],3); y = [math]::Round([double]$e['20'],3); layer = $layer; text = $txt }) | Out-Null
        }
        return
    }

    # 未识别类型(SPLINE/ELLIPSE/HATCH/DIMENSION 等)不解析几何, 但必须计数暴露,
    # 否则换图后几何被静默丢弃无从发现; BLOCK/VERTEX/SEQEND 为结构性图元, 不计
    if ($t -notin @('BLOCK','VERTEX','SEQEND')) {
        if ($script:unknownTypes.ContainsKey($t)) { $script:unknownTypes[$t]++ }
        else { $script:unknownTypes[$t] = 1 }
    }
}

$i = 0
$n = $lines.Count
while ($i -lt $n - 1) {
    $codeLine = $lines[$i].Trim()
    $val = $lines[$i+1]
    $i += 2
    if ($codeLine -eq '') { continue }
    $code = 0
    if (-not [int]::TryParse($codeLine, [ref]$code)) { continue }

    if ($code -eq 0) {
        if ($val -eq 'SECTION') { $section = ''; $cur = $null; continue }
        if ($val -eq 'ENDSEC')  { Flush-Entity $cur; $cur = $null; $curDef = $null; $inDefCtx = $false; $section = ''; continue }
        if ($val -eq 'EOF')     { Flush-Entity $cur; $cur = $null; break }
        if ($val -eq 'BLOCK') {
            Flush-Entity $cur
            $cur = @{ type = 'BLOCK'; pts = (New-Object System.Collections.Generic.List[object]) }
            $curDef = @{ base = @(0.0,0.0); segs = (New-Object System.Collections.Generic.List[object]); polys = (New-Object System.Collections.Generic.List[object]); ins = (New-Object System.Collections.Generic.List[object]); name = '' }
            $inDefCtx = $true
            continue
        }
        if ($val -eq 'ENDBLK') {
            Flush-Entity $cur; $cur = $null
            if ($curDef -ne $null -and $curDef.name -ne '' -and -not $curDef.name.StartsWith('*')) {
                $nm = $curDef.name
                $rawDefs[$nm] = @{ base = $curDef.base; segs = $curDef.segs; polys = $curDef.polys; ins = $curDef.ins }
            }
            $curDef = $null; $inDefCtx = $false
            continue
        }
        Flush-Entity $cur
        $cur = @{ type = $val; pts = (New-Object System.Collections.Generic.List[object]) }
        continue
    }

    if ($val -eq 'SECTION') { if ($code -eq 2) { $section = $cur['type']; }; $cur = $null; continue }

    if ($cur -eq $null) { continue }

    switch ($code) {
        8  { $cur['8'] = $val }
        2  { if ($cur['type'] -eq 'BLOCK') { if ($curDef.name -eq '') { $curDef.name = $val } } else { $cur['2'] = $val } }
        10 { if ($cur['type'] -eq 'BLOCK') { $curDef.base[0] = [double]$val } elseif ($cur['type'] -eq 'LWPOLYLINE') { $cur.pts.Add(@([math]::Round([double]$val,3), 0.0)) | Out-Null } else { $cur['10'] = $val } }
        20 { if ($cur['type'] -eq 'BLOCK') { $curDef.base[1] = [double]$val } elseif ($cur['type'] -eq 'LWPOLYLINE' -and $cur.pts.Count -gt 0) { $last = $cur.pts[$cur.pts.Count-1]; $cur.pts[$cur.pts.Count-1] = @($last[0], [math]::Round([double]$val,3)) } else { $cur['20'] = $val } }
        11 { $cur['11'] = $val }
        21 { $cur['21'] = $val }
        40 { $cur['40'] = $val }
        41 { $cur['41'] = $val }
        42 { $cur['42'] = $val }
        50 { $cur['50'] = $val }
        51 { $cur['51'] = $val }
        70 { $cur['70'] = $val }
        1  { $cur['1'] = $val }
        3  { if (-not $cur.ContainsKey('3')) { $cur['3'] = @() }; $cur['3'] += $val }
        67 { $cur['67'] = $val }
    }
}
Flush-Entity $cur

Write-Output ("raw defs: " + $rawDefs.Count)

# ---- resolve nested block definitions (flatten) ----
$resolved = @{}
function Resolve-Def([string]$name, [System.Collections.Generic.List[string]]$visited) {
    if ($script:resolved.ContainsKey($name)) { return $script:resolved[$name] }
    if (-not $script:rawDefs.ContainsKey($name)) { return $null }
    if ($visited.Contains($name)) { return $null }
    $visited.Add($name) | Out-Null
    $d = $script:rawDefs[$name]
    $segs = New-Object System.Collections.Generic.List[object]
    $polys = New-Object System.Collections.Generic.List[object]
    $bx = $d.base[0]; $by = $d.base[1]
    foreach ($s in $d.segs) {
        $segs.Add($s) | Out-Null
    }
    foreach ($p in $d.polys) {
        $polys.Add(@{ closed = $p.closed; pts = $p.pts }) | Out-Null
    }
    foreach ($ins in $d.ins) {
        $g2 = Resolve-Def $ins.name $visited
        if ($g2 -eq $null) { continue }
        $cb = $script:rawDefs[$ins.name].base
        $ca = [math]::Cos($ins.rot); $sa = [math]::Sin($ins.rot)
        foreach ($s in $g2.segs) {
            $ax = $s.x1 - $cb[0]; $ay = $s.y1 - $cb[1]
            $bx2 = $s.x2 - $cb[0]; $by2 = $s.y2 - $cb[1]
            $x1 = $ins.x + $ins.sx*($ca*$ax - $sa*$ay); $y1 = $ins.y + $ins.sy*($sa*$ax + $ca*$ay)
            $x2 = $ins.x + $ins.sx*($ca*$bx2 - $sa*$by2); $y2 = $ins.y + $ins.sy*($sa*$bx2 + $ca*$by2)
            $segs.Add((New-DefSeg $x1 $y1 $x2 $y2)) | Out-Null
        }
        foreach ($p in $g2.polys) {
            $np = @()
            foreach ($pt in $p.pts) {
                $ax = $pt[0] - $cb[0]; $ay = $pt[1] - $cb[1]
                $np += ,@([math]::Round($ins.x + $ins.sx*($ca*$ax - $sa*$ay),3), [math]::Round($ins.y + $ins.sy*($sa*$ax + $ca*$ay),3))
            }
            $polys.Add(@{ closed = $p.closed; pts = $np }) | Out-Null
        }
    }
    # bbox 从本定义最终展平几何统计。不能用跨作用域共享变量:
    # 旧实现 TrackPt 写 $script: 而此处读局部, bbox 恒为 0; 且 Resolve-Def
    # 递归时嵌套调用会覆盖共享变量, 统计必须放在几何全部生成之后
    $minx = [double]::PositiveInfinity; $miny = [double]::PositiveInfinity
    $maxx = [double]::NegativeInfinity; $maxy = [double]::NegativeInfinity
    foreach ($s in $segs) {
        if ($s.x1 -lt $minx) {$minx=$s.x1}; if ($s.x1 -gt $maxx) {$maxx=$s.x1}
        if ($s.y1 -lt $miny) {$miny=$s.y1}; if ($s.y1 -gt $maxy) {$maxy=$s.y1}
        if ($s.x2 -lt $minx) {$minx=$s.x2}; if ($s.x2 -gt $maxx) {$maxx=$s.x2}
        if ($s.y2 -lt $miny) {$miny=$s.y2}; if ($s.y2 -gt $maxy) {$maxy=$s.y2}
    }
    foreach ($p in $polys) {
        foreach ($pt in $p.pts) {
            if ($pt[0] -lt $minx) {$minx=$pt[0]}; if ($pt[0] -gt $maxx) {$maxx=$pt[0]}
            if ($pt[1] -lt $miny) {$miny=$pt[1]}; if ($pt[1] -gt $maxy) {$maxy=$pt[1]}
        }
    }
    $bbox = if ($minx -lt 1e17) { @{ minx=[math]::Round($minx,3); miny=[math]::Round($miny,3); maxx=[math]::Round($maxx,3); maxy=[math]::Round($maxy,3) } } else { @{ minx=0; miny=0; maxx=0; maxy=0 } }
    $r = @{ segs = $segs; polys = $polys; bbox = $bbox }
    $script:resolved[$name] = $r
    return $r
}

$allNames = @($rawDefs.Keys)
$visited = New-Object System.Collections.Generic.List[string]
foreach ($nm in $allNames) { Resolve-Def $nm $visited | Out-Null }
Write-Output ("resolved defs: " + $resolved.Count)

# 防呆: 什么都没解析出来就不写文件, 避免用空结果覆盖上一次的好数据
$total = $walls.Count + $shelv.Count + $glaz.Count + $cols.Count + $stairs.Count + `
    $grids.Count + $panels.Count + $doors.Count + $furnInsts.Count + $labels.Count + $resolved.Count
if ($total -eq 0) {
    Write-Output "ERROR: 未从输入解析出任何实体, 不写输出(避免覆盖已有 JSON)。请确认输入是文本格式的 DXF。"
    exit 1
}

# 输出统一 UTF-8 无 BOM(Windows PowerShell 5.1 的 Set-Content -Encoding UTF8 会带 BOM)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-JsonFile([string]$path, $obj, [int]$depth) {
    [System.IO.File]::WriteAllText($path, (ConvertTo-Json $obj -Depth $depth -Compress), $script:utf8NoBom)
}
Write-JsonFile "$outDir\walls.json" @{ segs = $walls } 5
Write-JsonFile "$outDir\shelving.json" @{ segs = $shelv } 5
Write-JsonFile "$outDir\glazing.json" @{ segs = $glaz } 5
Write-JsonFile "$outDir\columns.json" @{ segs = $cols } 5
Write-JsonFile "$outDir\stairs.json" @{ segs = $stairs } 5
Write-JsonFile "$outDir\grid.json" @{ segs = $grids } 5
Write-JsonFile "$outDir\panels.json" @{ polys = $panels } 5
Write-JsonFile "$outDir\doors.json" @{ insts = $doors } 5
Write-JsonFile "$outDir\furniture_instances.json" @{ insts = $furnInsts } 5
Write-JsonFile "$outDir\block_definitions.json" $resolved 6
Write-JsonFile "$outDir\labels.json" @{ labels = $labels } 5

Write-Output "== extracted =="
Write-Output ("walls:   " + $walls.Count)
Write-Output ("shelv:   " + $shelv.Count)
Write-Output ("glazing: " + $glaz.Count)
Write-Output ("columns: " + $cols.Count)
Write-Output ("stairs:  " + $stairs.Count)
Write-Output ("grid:    " + $grids.Count)
Write-Output ("panels:  " + $panels.Count)
Write-Output ("doors:   " + $doors.Count)
Write-Output ("furnI:   " + $furnInsts.Count)
Write-Output ("labels:  " + $labels.Count)
# 未分类图元: 不解析几何但如实报数; 换图后若模型缺几何, 先查这里
if ($unknownTypes.Count -gt 0) {
    $parts = $unknownTypes.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "$($_.Key)x$($_.Value)" }
    Write-Output ("未分类(已忽略): " + ($parts -join ', '))
} else {
    Write-Output "未分类: 0"
}
Write-Output "DONE"
