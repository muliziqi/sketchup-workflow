param(
    [string]$Json = '{"cmd":"ping"}',
    [string]$JsonFile = '',
    [int]$TimeoutSec = 150
)
$ErrorActionPreference = 'Stop'
if ($JsonFile -ne '') { $Json = [System.IO.File]::ReadAllText($JsonFile) }
$client = New-Object System.Net.Sockets.TcpClient
$task = $client.ConnectAsync('127.0.0.1', 5768)
try {
    if (-not $task.Wait(5000)) { Write-Output '{"ok":false,"error":"connect timeout - bridge not running"}'; exit 1 }
} catch {
    # 桥未启动时连接被拒, Wait 会抛 AggregateException —— 转成干净的 JSON 错误
    Write-Output '{"ok":false,"error":"connect failed - bridge not running"}'
    exit 1
}
$stream = $client.GetStream()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($Json + "`n")
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
$reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
# 旧实现用同步 ReadLine, 会一直阻塞到有数据, -TimeoutSec 形同虚设;
# 改为单次异步读 + 按超时上限整体等待, 慢 eval 期间桥不回包也能按期超时退出
$readTask = $reader.ReadLineAsync()
if (-not $readTask.Wait([int]($TimeoutSec * 1000))) {
    Write-Output ('{"ok":false,"error":"timeout: bridge did not respond within ' + $TimeoutSec + 's"}')
    $client.Close()
    exit 1
}
if ($readTask.IsFaulted) {
    $msg = $readTask.Exception.InnerException.Message
    Write-Output ('{"ok":false,"error":"bridge read error: ' + $msg + '"}')
    $client.Close()
    exit 1
}
$line = $readTask.Result
if ($null -eq $line) {
    Write-Output '{"ok":false,"error":"connection closed by bridge before response"}'
    $client.Close()
    exit 1
}
Write-Output $line
$client.Close()
