$ErrorActionPreference = 'Stop'
$dwg = 'D:\Apps\AutoCAD\AutoCAD 2027\Sample\Database Connectivity\Floor Plan Sample.dwg'
$dxf = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/floor_plan.dxf'
if (Test-Path $dxf) { Remove-Item $dxf -Force }

try {
    $acad = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application')
    Write-Output "reusing running AutoCAD"
} catch {
    $acad = New-Object -ComObject AutoCAD.Application
    Write-Output "launched new AutoCAD"
}
$acad.Visible = $true
$doc = $acad.Documents.Open($dwg, $true)
Write-Output "document opened"

$doc.SetVariable('FILEDIA', 0) | Out-Null
# path + precision 16 + Enter, then Enter on the format prompt (default = 2018 DXF)
$doc.SendCommand('._DXFOUT "' + $dxf + '" 16' + [char]10 + [char]10)

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
$doc.Close($false)
$acad.Quit()
Write-Output "DONE"
