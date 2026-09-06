param(
    [string]$Json = '{"cmd":"ping"}',
    [string]$JsonFile = '',
    [int]$TimeoutSec = 150
)
$ErrorActionPreference = 'Stop'
if ($JsonFile -ne '') { $Json = [System.IO.File]::ReadAllText($JsonFile) }
$client = New-Object System.Net.Sockets.TcpClient
$task = $client.ConnectAsync('127.0.0.1', 5768)
if (-not $task.Wait(5000)) { Write-Output '{"ok":false,"error":"connect timeout - bridge not running"}'; exit 1 }
$stream = $client.GetStream()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($Json + "`n")
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
$reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    $line = $reader.ReadLine()
    if ($null -ne $line) { Write-Output $line; break }
    Start-Sleep -Milliseconds 200
}
$client.Close()
