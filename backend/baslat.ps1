# Deprem Bildirim API - baslatma scripti
# Kullanim:  PowerShell'de  ->  .\baslat.ps1
#
# Bu script once 8000 portunu tutan kalmis (zombi) islemleri kapatir,
# sonra sunucuyu baslatir. Boylece WinError 10013 / 10048 hatasi olmaz.

$port = 8000

Write-Host "[1/2] $port portu kontrol ediliyor..." -ForegroundColor Cyan
$conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($conns) {
    foreach ($c in $conns) {
        Write-Host ("      Kalmis islem kapatiliyor: PID {0}" -f $c.OwningProcess) -ForegroundColor Yellow
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 800
} else {
    Write-Host "      Port bos, temiz." -ForegroundColor Green
}

Write-Host "[2/2] Sunucu baslatiliyor -> http://127.0.0.1:$port/docs" -ForegroundColor Cyan
Write-Host "      Durdurmak icin Ctrl+C." -ForegroundColor DarkGray
uvicorn src.main:app --reload --port $port
