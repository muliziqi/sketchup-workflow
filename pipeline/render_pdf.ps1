param(
    [string]$PdfPath = '',
    [string]$OutDir = '',
    [int]$MaxPages = 12,
    [double]$Scale = 2.0
)
$ErrorActionPreference = 'Stop'

# ---- 路径三级回退: 脚本所在目录(仓库根) -> $env:SKWF_HOME -> 用户目录 ----
if ($PSScriptRoot)      { $skwfRoot = Split-Path $PSScriptRoot -Parent }
elseif ($env:SKWF_HOME) { $skwfRoot = $env:SKWF_HOME }
else                    { $skwfRoot = Join-Path $HOME 'sketchup-workflow' }

# 输入 PDF 缺省: 仓库根\latapie_drawings.pdf -> 仓库根下任一 PDF
if (-not $PdfPath) {
    $cand = @((Join-Path $skwfRoot 'latapie_drawings.pdf'))
    $any = Get-ChildItem -Path $skwfRoot -Filter '*.pdf' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($any) { $cand += $any.FullName }
    $PdfPath = $cand | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $PdfPath) {
        Write-Output "ERROR: 未指定 PDF。用法: render_pdf.ps1 -PdfPath <文件.pdf> [-OutDir <输出目录>]"
        Write-Output "(缺省按 仓库根\latapie_drawings.pdf -> 仓库根下任一 PDF 查找; 可用 SKWF_HOME 指定工作根)"
        exit 1
    }
}
# 输出目录缺省: PDF 同目录下的 pages\
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PdfPath -Parent) 'pages' }

# WinRT 投影(Windows PowerShell 5.1)
[void][Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFolder, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.RandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}
$asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function AwaitAction($WinRtAction) {
    $netTask = $asTaskAction.Invoke($null, @($WinRtAction))
    $netTask.Wait(-1) | Out-Null
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($PdfPath)) ([Windows.Storage.StorageFile])
$pdf = Await ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
$count = [Math]::Min($pdf.PageCount, $MaxPages)
Write-Output ("pages: {0} (render {1})" -f $pdf.PageCount, $count)

$folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($OutDir)) ([Windows.Storage.StorageFolder])

for ($i = 0; $i -lt $count; $i++) {
    $page = $pdf.GetPage($i)
    $name = "page_{0:d2}.png" -f ($i + 1)
    $imgFile = Await ($folder.CreateFileAsync($name, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
    $stream = Await ($imgFile.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)) ([Windows.Storage.Streams.IRandomAccessStream])
    $stream.Size = 0
    $opts = New-Object Windows.Data.Pdf.PdfPageRenderOptions
    # 尺寸先缓存再 Dispose: 释放后再读 $page.Size 拿到的是已释放对象
    $w = [math]::Round($page.Size.Width * $Scale)
    $h = [math]::Round($page.Size.Height * $Scale)
    $opts.DestinationWidth = [uint32]$w
    $opts.DestinationHeight = [uint32]$h
    AwaitAction ($page.RenderToStreamAsync($stream, $opts))
    $stream.Dispose()
    $page.Dispose()
    Write-Output ("  {0}  {1}x{2}" -f $name, $w, $h)
}
Write-Output "RENDER DONE"
