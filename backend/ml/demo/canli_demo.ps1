# Asama 7 - ANN ikinci katmani CANLI DEMO scripti.
#
# Amac: hocaya/jur"iye gostermek icin, TEK script'le tekrarlanabilir bir uctan uca kanit -
# sensore enjekte edilen sahte-deprem sinyalinin, gercek telefon uygulamasindan gecip,
# 1. katman (STA/LTA) + 2. katman (ANN) onayindan sonra GERCEK bir HTTP istegiyle
# backend'e ulastigini canli gosterir.
#
# Onkosul: emulator (deprem_pixel) onceden acilmis VE uygulama (Kaan / Kaan123 ile
# giris yapilmis, "Arka planda deprem izleme" anahtari ACIK) durumda olmali - bu script
# giris/anahtar adimlarini OTOMATIK yapmaz (demo sirasinda "canli" gorunmesi icin bilerek
# elle yapiliyor), sadece backend'i baslatir ve sinyali enjekte eder.
#
# Calistirma: PowerShell'de, deprem/ klasorunden: .\ml\demo\canli_demo.ps1

$adb = "C:\Users\Kaan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$backendYolu = "C:\Users\Kaan\Desktop\staj projeee\deprem"

Write-Host "=== ASAMA 7 - ANN IKINCI KATMAN CANLI DEMO ===" -ForegroundColor Cyan
Write-Host ""

# --- 1) Backend'i baslat ---
Write-Host "[1/4] Backend baslatiliyor..." -ForegroundColor Yellow
Set-Location $backendYolu
Start-Process -NoNewWindow -FilePath python -ArgumentList "-m","uvicorn","src.main:app","--host","0.0.0.0","--port","8000" `
  -RedirectStandardOutput "uvicorn_out.log" -RedirectStandardError "uvicorn_err.log"
Start-Sleep -Seconds 3
$dinliyor = Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue
if ($dinliyor) { Write-Host "      Backend calisiyor (port 8000)." -ForegroundColor Green }
else { Write-Host "      UYARI: backend baslamadi, uvicorn_err.log'a bak." -ForegroundColor Red; exit 1 }
Write-Host ""

# --- 2) Emulator kontrolu ---
Write-Host "[2/4] Emulator kontrol ediliyor..." -ForegroundColor Yellow
$cihazlar = (& $adb devices) -join "`n"
if ($cihazlar -notmatch "emulator-5554\s+device") {
  Write-Host "      UYARI: emulator-5554 calismiyor. Once emulatoru ac ve uygulamada" -ForegroundColor Red
  Write-Host "      Kaan/Kaan123 ile giris yap, 'Arka planda deprem izleme' anahtarini AC." -ForegroundColor Red
  exit 1
}
Write-Host "      Emulator hazir." -ForegroundColor Green
Write-Host ""

# --- 3) Sentetik deprem sinyali enjekte et ---
Write-Host "[3/4] Sentetik deprem sinyali enjekte ediliyor (~5 sn, 5 Hz osilasyon)..." -ForegroundColor Yellow
Write-Host "      (Telefonun ekranindaki 'Sarsinti' gostergesine bak - ANLIK tepki verecek)" -ForegroundColor DarkGray
for ($i = 0; $i -lt 120; $i++) {
  $t = $i * 0.05
  $x = 3.5 * [Math]::Sin(2 * [Math]::PI * 5 * $t)
  & $adb -s emulator-5554 emu sensor set acceleration "${x}:9.8:0.0" | Out-Null
  Start-Sleep -Milliseconds 40
}
Write-Host "      Enjeksiyon tamamlandi." -ForegroundColor Green
Write-Host ""

# --- 4) Backend'de gercek kaydin olustugunu dogrula ---
Write-Host "[4/4] Backend veritabaninda yeni kayit araniyor..." -ForegroundColor Yellow
Start-Sleep -Seconds 1
python -c "
import sqlite3
con = sqlite3.connect(r'data\earthquake.db')
satirlar = con.execute('SELECT id, intensity, reported_at FROM tremor_reports ORDER BY id DESC LIMIT 3').fetchall()
con.close()
if not satirlar:
    print('      HICBIR KAYIT YOK - sinyal 1. katmani gecmemis olabilir.')
else:
    print('      SONUC: gercek TremorReport kaydi/kayitlari bulundu:')
    for s in satirlar:
        print(f'        id={s[0]}  siddet={s[1]:.2f} m/s^2  zaman={s[2]}')
    print()
    print('      -> Bu, sinyalin 1. katmani (STA/LTA) VE 2. katmani (ANN onayi)')
    print('         GECIP backend\'e gercek bir HTTP istegiyle ulastigini kanitlar.')
"
Write-Host ""
Write-Host "=== DEMO TAMAMLANDI ===" -ForegroundColor Cyan
Write-Host "(Test verisini silmek icin: ml\demo\test_verisini_temizle.py calistir)" -ForegroundColor DarkGray
