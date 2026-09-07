import threading
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from src.database import get_session
from src.users.models import User
from src.notify.models import Notification
from src.quakes.models import Earthquake
from src.tremor.models import TremorReport
from src.detect.models import (
    DetectionEvent,
    DetectionEventPublic,
    DetectionStatus,
    PreliminaryAlert,
    FeltReport,
    FeltReportCreate,
    FeltReportPublic,
)
from src.auth.router import admin_gerekli, aktif_kullanici
from src.notify.router import haversine_km, ek_konum_mesafeleri
from src.notify.push import push_gonder

router = APIRouter(
    prefix="/detections",
    tags=["Detections"],
)


ZAMAN_PENCERESI_DK = 5
YARICAP_KM = 2
MIN_KULLANICI = 3
ALARM_ESIK = 40         # bildirim icin gereken min rapor (kucuk kumeler pending kalir, alarm gitmez)

# OLGUNLASMA PENCERESI: bir rapor, olusturulduktan en az bu kadar saniye sonra kumeleme
# icin aday sayilir. Gercek paralel HTTP trafiginde (ornegin 50-200 rapor ayni anda
# gelirse) her istekten hemen sonra calisan tespit, henuz "olgunlasmamis" (cok taze)
# raporlari GORMEZDEN GELIR — boylece tek fiziksel patlama, ilk 3 kisi geldigi an
# erkenden kucuk parcalara bolunmez. Dalga tamamen "olgunlastiktan" sonra (script veya
# bir sonraki istek) calisan tespit, TUM raporlari TEK seferde tek kumede degerlendirir.
# Deger, buyuk (200+ kullanicili) bir dalganin SQLite'in tek-yazarli kilidi yuzunden
# gonderilmesi bile birkac saniye surebilecegi icin cömertce secildi (dalga BITERKEN
# hala erken raporlar 'olgunlasip' ortadan bolunmesin diye). Organik/tekil kullanim
# icin etkisi ihmal edilebilir (5 dakikalik pencerenin yaninda birkac saniye).
TAZE_RAPOR_BEKLEME_SN = 6

# Kandilli dogrulama esikleri
DOGRULAMA_YARICAP_KM = 50   # tespit merkezi ile resmi deprem arasi max mesafe (km)
DOGRULAMA_ZAMAN_DK = 15     # tespit ile resmi deprem arasi max zaman farki (dk)

# Sahte-pozitif takibi (Asama 1): bu kadar saat pending kalip hicbir resmi depremle
# eslesmeyen bir tespit, artik "muhtemelen yanlis alarmdi" sayilip false_positive isaretlenir.
ESKIME_SAAT = 48

# Mesafe bazli erken uyari (Asama 5): ayri, HIZLI bir "on uyari" katmani. TremorReport
# tablosunu SADECE OKUR (detection_event_id'ye HIC DOKUNMAZ) — aksi halde bu raporlar
# yavas/kesinlesmis 40-kullanicili alarmin kumeleme sorgusundan (detection_event_id ==
# None filtresi) SONSUZA KADAR kaybolurdu, gercek depremin toplam rapor sayisi eksik kalirdi.
ERKEN_UYARI_ZAMAN_PENCERESI_SN = 45  # bu kadar taze rapor aday sayilir — OLGUNLASMA PENCERESI YOK (hiz > kesinlik)
ERKEN_UYARI_MIN_MESAFE_KM = 15       # bundan yakin kullanicilara pay yok (zaten hissetmis/rapor gondermis olabilir)
ERKEN_UYARI_TEKRAR_ENGELLEME_DK = 10  # bu sure icinde YAKIN bir on uyari varsa tekrar ATESLENMEZ
ERKEN_UYARI_TEKRAR_YARICAP_KM = 5     # kumeleme yaricapindan (2km) GEVSEK — kutle merkezi rapor
                                       # sayisi arttikca kayar, cok siki bir yaricap "yeni" sanip tekrar atesler
P_DALGA_HIZ_KM_SN = 6.0                # kaba P-dalgasi hizi (km/sn) — ETA hesaplamasi icin

# Ayni fiziksel olay icin erken_uyari_tetikle'nin (check-then-insert) yarisdurumuna (race
# condition) karsi basit bir kilit. YETERLI cunku backend TEK PROCESS calisiyor (kanit:
# baslat.ps1 ve tum oturum boyunca kullanilan komutlar "uvicorn src.main:app --reload ..."
# — --workers YOK). Ileride birden fazla process/worker'a gecilirse bu YETERSIZ kalir,
# DB seviyesinde bir kilit gerekir.
_erken_uyari_kilidi = threading.Lock()


def _kumele(raporlar: list[TremorReport], yaricap_km: float) -> list[list[TremorReport]]:
    """Verilen rapor listesini, MIN_KULLANICI (farkli kullanici sayisi) esigini gecen
    cografi kumelere ayirir. Hem yavas (olasi_depremleri_tespit_et) hem hizli
    (erken_uyari_adaylarini_bul) yol AYNI kumeleme mantigini kullanir — kod tekrari yok."""
    kullanilmis: set[int] = set()
    kumeler: list[list[TremorReport]] = []

    for cekirdek in raporlar:
        if cekirdek.id in kullanilmis:
            continue
        komsuluk = [
            r for r in raporlar
            if r.id not in kullanilmis
            and haversine_km(cekirdek.latitude, cekirdek.longitude, r.latitude, r.longitude) <= yaricap_km
        ]
        farkli_kullanicilar = {r.user_id for r in komsuluk}
        if len(farkli_kullanicilar) >= MIN_KULLANICI:
            kumeler.append(komsuluk)
            kullanilmis.update(r.id for r in komsuluk)
    return kumeler


def olasi_depremleri_tespit_et(session: Session) -> list[list[TremorReport]]:
    esik_zaman = datetime.utcnow() - timedelta(minutes=ZAMAN_PENCERESI_DK)
    olgunlasma_siniri = datetime.utcnow() - timedelta(seconds=TAZE_RAPOR_BEKLEME_SN)
    adaylar = session.exec(
        select(TremorReport).where(
            TremorReport.detection_event_id == None,
            TremorReport.reported_at >= esik_zaman,
            TremorReport.reported_at <= olgunlasma_siniri,  # cok taze raporlar henuz aday degil
        )
    ).all()
    return _kumele(adaylar, YARICAP_KM)


def tespit_et_ve_kaydet(session: Session) -> list[DetectionEvent]:
    kumeler = olasi_depremleri_tespit_et(session)
    olusan_olaylar: list[DetectionEvent] = []

    for kume in kumeler:
        n = len(kume)

        merkez_lat = sum(r.latitude for r in kume) / n
        merkez_lon = sum(r.longitude for r in kume) / n
        ortalama_buyukluk = sum(r.intensity for r in kume) / n

        olay = DetectionEvent(
            center_lat=merkez_lat,
            center_lon=merkez_lon,
            estimated_magnitude=ortalama_buyukluk,
            report_count=n,
        )
        session.add(olay)
        session.commit()
        session.refresh(olay)
        for r in kume:
            r.detection_event_id = olay.id
            session.add(r)
        session.commit()


        olay_icin_bildirim_olustur(session, olay)

        olusan_olaylar.append(olay)

    return olusan_olaylar


def olay_icin_kullanicilari_bul(session: Session, olay: DetectionEvent) -> list[User]:
    statement = select(User).where(
        User.pref_min_magnitude != None,
        User.pref_min_magnitude <= olay.estimated_magnitude,
    )
    adaylar = session.exec(statement).all()

    uygun_kullanicilar = []
    for user in adaylar:
        if user.pref_latitude is None or user.pref_radius_km is None:
            continue
        mesafe = haversine_km(user.pref_latitude, user.pref_longitude, olay.center_lat, olay.center_lon)
        if mesafe <= user.pref_radius_km:
            uygun_kullanicilar.append(user)

    return uygun_kullanicilar


def _kullaniciya_yakinda_erken_uyari_gitti_mi(session: Session, user_id: int) -> bool:
    """Bu kullaniciya son ERKEN_UYARI_TEKRAR_ENGELLEME_DK dakikada "ERKEN UYARI:" onekli
    bir bildirim gitti mi diye GEVSEK/yaklasik bir kontrol — Kandilli dedup'indaki gibi TAM
    bir FK eslesmesi DEGIL, cunku on uyari ile kesinlesmis alarm arasinda stabil bir bag
    (foreign key) yok. Bilincli bir yaklasiklik: dusuk olasilikli/dusuk etkili bir hata
    payi (iki alakasiz kucuk olay ust uste gelirse yanlis "GUNCELLEME" mesaji) kabul edilir."""
    esik = datetime.utcnow() - timedelta(minutes=ERKEN_UYARI_TEKRAR_ENGELLEME_DK)
    var_mi = session.exec(
        select(Notification).where(
            Notification.user_id == user_id,
            Notification.matched_reason.like("ERKEN UYARI:%"),
            Notification.created_at >= esik,
        )
    ).first()
    return var_mi is not None


def olay_icin_bildirim_olustur(session: Session, olay: DetectionEvent) -> int:
    if olay.report_count < ALARM_ESIK:
        return 0

    kullanicilar = olay_icin_kullanicilari_bul(session, olay)
    sayac = 0
    for user in kullanicilar:
        mesafe = haversine_km(user.pref_latitude, user.pref_longitude, olay.center_lat, olay.center_lon)
        # Uc katmanli bildirim uyumu (Asama 5): bu kullanici az once bu depremin ERKEN
        # UYARISINI almissa, ayni anlamdaki ikinci bir "UYARI:" yerine "dogrulandi" mesaji.
        if _kullaniciya_yakinda_erken_uyari_gitti_mi(session, user.id):
            mesaj = (f"GUNCELLEME: Erken uyariniz dogrulandi — {olay.report_count} kullanici "
                     f"bildirdi, buyukluk ~{olay.estimated_magnitude:.1f}")
        else:
            mesaj = f"UYARI: Bölgenizde olasi deprem! Büyüklük ~{olay.estimated_magnitude:.1f}, size {mesafe:.1f} km uzakta"
        bildirim = Notification(
            detection_event_id=olay.id,
            user_id=user.id,
            matched_reason=mesaj,
        )
        session.add(bildirim)
        sayac += 1
        # Gercek push (Faz 4): DB kaydi birincil, push ikincil — hata firlatmaz.
        # data payload: mobil taraf (kritik_bildirim_servisi.dart) bunu gorunce
        # full-screen-intent bildirimiyle EarthquakeAlertScreen'i OTOMATIK acar
        # (bildirime dokunmaya gerek kalmadan). sistem_bildirimi_olustur=False:
        # mobil taraf kendi bildirimini olusturuyor, FCM'in otomatik gosterdigi
        # bildirimle CIFT bildirim olmasin diye `notification` blogu atlanir.
        push_gonder(
            user.fcm_token,
            "Deprem Uyarisi!",
            mesaj,
            data={
                "type": "earthquake_alert",
                "magnitude": f"{olay.estimated_magnitude:.1f}",
                "distance_km": f"{mesafe:.0f}",
            },
            sistem_bildirimi_olustur=False,
        )

    # Ek konumlar (Ev/Isyeri) — birincil konumdan BAGIMSIZ, kendi yaricap/esigine gore.
    # Kritik crowd alarmi oldugu icin bunlar da tam-ekran-intent tetikler.
    for user, konum, mesafe in ek_konum_mesafeleri(session, olay.center_lat, olay.center_lon):
        if mesafe > konum.radius_km or konum.min_magnitude > olay.estimated_magnitude:
            continue
        mesaj = (f"EK KONUM ({konum.etiket}): Bölgesinde olasi deprem! "
                 f"Büyüklük ~{olay.estimated_magnitude:.1f}, {mesafe:.1f} km uzakta")
        session.add(Notification(detection_event_id=olay.id, user_id=user.id, matched_reason=mesaj))
        sayac += 1
        push_gonder(
            user.fcm_token,
            f"Deprem Uyarisi! ({konum.etiket})",
            mesaj,
            data={
                "type": "earthquake_alert",
                "magnitude": f"{olay.estimated_magnitude:.1f}",
                "distance_km": f"{mesafe:.0f}",
            },
            sistem_bildirimi_olustur=False,
        )

    session.commit()
    return sayac


def erken_uyari_adaylarini_bul(session: Session) -> list[list[TremorReport]]:
    """Yavas yoldan (olasi_depremleri_tespit_et) TEK farki: OLGUNLASMA PENCERESI YOK —
    hiz bu katmanin tek amaci. Sadece henuz hic kumelenmemis (detection_event_id == None)
    ve ERKEN_UYARI_ZAMAN_PENCERESI_SN icindeki raporlara bakar."""
    esik_zaman = datetime.utcnow() - timedelta(seconds=ERKEN_UYARI_ZAMAN_PENCERESI_SN)
    adaylar = session.exec(
        select(TremorReport).where(
            TremorReport.detection_event_id == None,
            TremorReport.reported_at >= esik_zaman,
        )
    ).all()
    return _kumele(adaylar, YARICAP_KM)


def erken_uyari_zaten_var_mi(session: Session, merkez_lat: float, merkez_lon: float) -> bool:
    """AYNI fiziksel olay icin erken uyarinin TEKRAR TEKRAR atesenmesini engelleyen asil
    mekanizma — olgunlasma penceresinin (TAZE_RAPOR_BEKLEME_SN, 'bekle') YERINE gecen,
    tamamen FARKLI bir cozum ('zaten uyardik mi diye bak'). Yarizap kumeleme yaricapindan
    (2km) GEVSEK (5km) cunku kutle merkezi rapor sayisi arttikca kayar."""
    esik_zaman = datetime.utcnow() - timedelta(minutes=ERKEN_UYARI_TEKRAR_ENGELLEME_DK)
    yakinlar = session.exec(
        select(PreliminaryAlert).where(PreliminaryAlert.created_at >= esik_zaman)
    ).all()
    for uyari in yakinlar:
        if haversine_km(uyari.center_lat, uyari.center_lon, merkez_lat, merkez_lon) <= ERKEN_UYARI_TEKRAR_YARICAP_KM:
            return True
    return False


def erken_uyari_icin_kullanicilari_bul(session: Session, uyari: PreliminaryAlert) -> list[tuple[User, float]]:
    """depreme_uygun_kullanicilari_bul'un aksine pref_min_magnitude FILTRESI YOK — 3
    kisinin oz-bildirdigi siddet kullanilabilir bir buyukluk tahmini DEGIL (bilincli kapsam
    karari). Mesafe >= ERKEN_UYARI_MIN_KM (yakinlarin zaten hissetmis/rapor gondermis olma
    ihtimali yuksek, onlara pay yok) ve <= pref_radius_km. Donen: (kullanici, mesafe) ciftleri."""
    adaylar = session.exec(
        select(User).where(User.pref_latitude != None, User.pref_longitude != None, User.pref_radius_km != None)
    ).all()

    sonuc: list[tuple[User, float]] = []
    for user in adaylar:
        mesafe = haversine_km(user.pref_latitude, user.pref_longitude, uyari.center_lat, uyari.center_lon)
        if ERKEN_UYARI_MIN_MESAFE_KM <= mesafe <= user.pref_radius_km:
            sonuc.append((user, mesafe))
    return sonuc


def erken_uyari_bildirimi_olustur(session: Session, uyari: PreliminaryAlert) -> int:
    """Her uygun kullanici icin tahmini varis suresini (kaba P-dalgasi hiziyla) hesaplayip
    'ERKEN UYARI:' onekli bir Notification yazar + push gonderir."""
    sayac = 0
    for user, mesafe in erken_uyari_icin_kullanicilari_bul(session, uyari):
        eta_sn = mesafe / P_DALGA_HIZ_KM_SN
        mesaj = (f"ERKEN UYARI: Olasi deprem tespit edildi — tahmini ~{eta_sn:.0f} sn icinde "
                 f"sizde hissedilebilir (~{mesafe:.0f} km)")
        bildirim = Notification(
            user_id=user.id,
            matched_reason=mesaj,
        )
        session.add(bildirim)
        sayac += 1
        push_gonder(user.fcm_token, "Erken Deprem Uyarisi!", mesaj)

    # Ek konumlar — burada da (birincil konumdaki gibi) BILINCLI OLARAK magnitude
    # filtresi yok, sadece ERKEN_UYARI_MIN_MESAFE_KM..radius_km bandi.
    for user, konum, mesafe in ek_konum_mesafeleri(session, uyari.center_lat, uyari.center_lon):
        if not (ERKEN_UYARI_MIN_MESAFE_KM <= mesafe <= konum.radius_km):
            continue
        eta_sn = mesafe / P_DALGA_HIZ_KM_SN
        mesaj = (f"EK KONUM ({konum.etiket}) ERKEN UYARI: Olasi deprem tespit edildi — "
                 f"tahmini ~{eta_sn:.0f} sn icinde hissedilebilir (~{mesafe:.0f} km)")
        session.add(Notification(user_id=user.id, matched_reason=mesaj))
        sayac += 1
        push_gonder(user.fcm_token, f"Erken Deprem Uyarisi! ({konum.etiket})", mesaj)

    session.commit()
    return sayac


def erken_uyari_tetikle(session: Session) -> list[PreliminaryAlert]:
    """Aday kumeleri bulur, HER kume icin 'zaten uyardik mi' guard'ini kontrol eder, gecen
    kumeler icin PreliminaryAlert kaydeder + bildirimleri olusturur. Kilit (bkz.
    _erken_uyari_kilidi), check-then-insert yarisdurumuna karsi (bkz. modul basi not)."""
    with _erken_uyari_kilidi:
        kumeler = erken_uyari_adaylarini_bul(session)
        olusanlar: list[PreliminaryAlert] = []

        for kume in kumeler:
            n = len(kume)
            merkez_lat = sum(r.latitude for r in kume) / n
            merkez_lon = sum(r.longitude for r in kume) / n

            if erken_uyari_zaten_var_mi(session, merkez_lat, merkez_lon):
                continue

            uyari = PreliminaryAlert(center_lat=merkez_lat, center_lon=merkez_lon, report_count=n)
            session.add(uyari)
            session.commit()
            session.refresh(uyari)

            erken_uyari_bildirimi_olustur(session, uyari)
            olusanlar.append(uyari)

        return olusanlar


def dogrulama_bildirimi_olustur(session: Session, tespit: DetectionEvent, deprem: Earthquake) -> int:
    """Bir tespit resmi deprem ile dogrulaninca, ilgili kullanicilara ikinci (resmi) bildirimi olusturur.
    Bu bildirim earthquake_id ile kurulur (crowd uyarisi detection_event_id'liydi) — kaynak ayrimi.

    IDEMPOTENT KONTROL: gercek paralel HTTP trafiginde tek bir fiziksel deprem, kumeleme
    algoritmasinin parcalanmasi yuzunden BIRDEN COK DetectionEvent'e bolunebilir (bkz. Not).
    tespitleri_dogrula bu parcalarin HERBIRINI ayni Earthquake'e baglayabilir; bu fonksiyon
    her cagrildiginda kontrolsuzce bildirim/push uretirse AYNI kullanici AYNI deprem icin
    onlarca kez "Kandilli dogruladi" bildirimi/push'u alir (spam). Bunu onlemek icin: bir
    kullaniciya bu deprem icin DAHA ONCE (bu veya onceki bir tespit uzerinden) bildirim
    gittiyse atlanir. session.exec autoflush sayesinde ayni tespitleri_dogrula kosusu
    icindeki henuz commit edilmemis eklemeler de bu kontrolde gorulur.
    """
    kullanicilar = olay_icin_kullanicilari_bul(session, tespit)
    yer = deprem.location_name or "bilinmeyen konum"
    sayac = 0
    for user in kullanicilar:
        # DIKKAT: sadece BU FONKSIYONUN urettigi "Kandilli dogruladi:" mesajlarina karsi
        # dedupe et — POST /test/earthquakes/ ayni (earthquake_id, user_id) icin FARKLI bir
        # mesajla (depreme_uygun_kullanicilari_bul uzerinden) da bildirim yaratabilir; onu
        # "zaten teyit gitmis" sanip GERCEK Kandilli teyidini atlamamak icin filtre daraltildi.
        zaten_bildirilmis = session.exec(
            select(Notification).where(
                Notification.earthquake_id == deprem.id,
                Notification.user_id == user.id,
                Notification.matched_reason.like("Kandilli dogruladi:%"),
            )
        ).first()
        if zaten_bildirilmis:
            continue
        mesaj = f"Kandilli dogruladi: M{deprem.magnitude:.1f}, derinlik {deprem.depth_km:.1f} km, {yer}"
        bildirim = Notification(
            earthquake_id=deprem.id,
            user_id=user.id,
            matched_reason=mesaj,
        )
        session.add(bildirim)
        sayac += 1
        # Gercek push (Faz 4): resmi teyit de telefona duser.
        push_gonder(user.fcm_token, "Kandilli Teyidi", mesaj)

    # Ek konumlar — ayni idempotent-dedupe deseni, etiket bazinda (iki ayri ek
    # konum ayni depremi dogrulatirsa ikisi de kendi tekil mesajini almali).
    for user, konum, mesafe in ek_konum_mesafeleri(session, tespit.center_lat, tespit.center_lon):
        if mesafe > konum.radius_km or konum.min_magnitude > tespit.estimated_magnitude:
            continue
        onek = f"EK KONUM ({konum.etiket}) Kandilli dogruladi:"
        zaten_bildirilmis = session.exec(
            select(Notification).where(
                Notification.earthquake_id == deprem.id,
                Notification.user_id == user.id,
                Notification.matched_reason.like(f"{onek}%"),
            )
        ).first()
        if zaten_bildirilmis:
            continue
        mesaj = f"{onek} M{deprem.magnitude:.1f}, derinlik {deprem.depth_km:.1f} km, {yer}"
        session.add(Notification(earthquake_id=deprem.id, user_id=user.id, matched_reason=mesaj))
        sayac += 1
        push_gonder(user.fcm_token, f"Kandilli Teyidi ({konum.etiket})", mesaj)

    session.commit()
    return sayac


def tespitleri_dogrula(session: Session) -> list[DetectionEvent]:
    """pending tespitleri resmi Earthquake kayitlariyla (konum + zaman) eslestirir.
    Eslesen tespit 'confirmed' olur, matched_earthquake_id dolar ve ikinci bildirim gonderilir.
    Donen deger: bu calistirmada dogrulanan tespitlerin listesi.
    """
    bekleyenler = session.exec(
        select(DetectionEvent).where(DetectionEvent.status == DetectionStatus.pending)
    ).all()
    depremler = session.exec(select(Earthquake)).all()

    dogrulananlar = []
    for tespit in bekleyenler:
        for deprem in depremler:
            mesafe = haversine_km(tespit.center_lat, tespit.center_lon, deprem.latitude, deprem.longitude)
            zaman_farki = abs((tespit.created_at - deprem.occurred_at).total_seconds())
            if mesafe <= DOGRULAMA_YARICAP_KM and zaman_farki <= DOGRULAMA_ZAMAN_DK * 60:
                tespit.matched_earthquake_id = deprem.id
                tespit.status = DetectionStatus.confirmed
                session.add(tespit)
                session.commit()
                session.refresh(tespit)
                dogrulama_bildirimi_olustur(session, tespit, deprem)
                dogrulananlar.append(tespit)
                break  # bir tespit ilk eslesen depreme baglanir

    return dogrulananlar


def eskimis_tespitleri_isaretle(session: Session, esik_saat: int = ESKIME_SAAT) -> int:
    """Uzun sure (varsayilan 48 saat) pending kalip hicbir resmi depremle eslesmeyen
    tespitleri false_positive olarak isaretler. DetectionStatus.false_positive daha once
    hic atanmiyordu (kod taramasiyla dogrulandi) — bu, o eksik parcayi tamamlayan fonksiyon.
    Donen deger: bu calistirmada false_positive yapilan tespit sayisi (bilgi/log amacli)."""
    esik_zaman = datetime.utcnow() - timedelta(hours=esik_saat)
    eskimisler = session.exec(
        select(DetectionEvent).where(
            DetectionEvent.status == DetectionStatus.pending,
            DetectionEvent.created_at <= esik_zaman,
        )
    ).all()
    for tespit in eskimisler:
        tespit.status = DetectionStatus.false_positive
        session.add(tespit)
    session.commit()
    return len(eskimisler)


def _saat_bolge_istatistigi(session: Session) -> dict:
    """Tum DetectionEvent'leri saat dilimine ve kaba bir cografi izgaraya (0.5 derece)
    gore ozetler. Amac: 'hangi bolgede/saatte yanlis-pozitif orani daha yuksek' gibi
    sorulari sayisallastirmak (bkz. plan: Asama 1 — analiz paneli)."""
    tumu = session.exec(select(DetectionEvent)).all()

    saat_ozeti: dict[int, dict[str, int]] = {}
    bolge_ozeti: dict[str, dict] = {}

    for t in tumu:
        saat = t.created_at.hour
        s = saat_ozeti.setdefault(
            saat, {"toplam": 0, "pending": 0, "confirmed": 0, "false_positive": 0}
        )
        s["toplam"] += 1
        s[t.status.value] += 1

        # 0.5 derecelik kaba izgara: lat/lon'u en yakin 0.5'e yuvarla (~55 km hucre).
        grid_lat = round(t.center_lat * 2) / 2
        grid_lon = round(t.center_lon * 2) / 2
        anahtar = f"{grid_lat},{grid_lon}"
        b = bolge_ozeti.setdefault(
            anahtar,
            {"toplam": 0, "pending": 0, "confirmed": 0, "false_positive": 0, "_rapor_toplami": 0},
        )
        b["toplam"] += 1
        b[t.status.value] += 1
        b["_rapor_toplami"] += t.report_count

    bolge_listesi = []
    for grid, veri in bolge_ozeti.items():
        rapor_toplami = veri.pop("_rapor_toplami")
        ortalama = rapor_toplami / veri["toplam"] if veri["toplam"] else 0
        bolge_listesi.append({"grid": grid, **veri, "ortalama_rapor_sayisi": round(ortalama, 1)})

    saat_listesi = [{"saat": saat, **veri} for saat, veri in sorted(saat_ozeti.items())]

    return {"saat_dilimi": saat_listesi, "bolge": bolge_listesi}


def _detection_public_ile_geri_bildirim(session: Session, olay: DetectionEvent) -> DetectionEventPublic:
    """DetectionEvent'i, ilgili FeltReport'lardan HESAPLANAN 'hissettim mi?' ozetiyle
    (oy_sayisi, ortalama_siddet) birlikte DetectionEventPublic'e cevirir. Bu iki alan
    DetectionEvent tablosunda KOLON olarak yok — her istekte YENIDEN hesaplaniyor, cunku
    oy sayisi zamanla degisir ve DetectionEvent'in kendisini her yeni oyda GUNCELLEMEK
    (ayrica bir yazma islemi) gereksiz karmasiklik olurdu."""
    oylar = session.exec(select(FeltReport).where(FeltReport.detection_event_id == olay.id)).all()
    oy_sayisi = len(oylar)
    ortalama_siddet = round(sum(o.siddet for o in oylar) / oy_sayisi, 1) if oy_sayisi else None
    return DetectionEventPublic(
        **olay.model_dump(),
        oy_sayisi=oy_sayisi,
        ortalama_siddet=ortalama_siddet,
    )


@router.get("/aktif/", response_model=list[DetectionEventPublic], summary="Son 24 saatteki tespitler (harita icin)")
def get_aktif_detections(
    *,
    session: Session = Depends(get_session),
    user: User = Depends(aktif_kullanici),  # admin DEGIL — girisli her kullanici (harita ekrani)
):
    esik = datetime.utcnow() - timedelta(hours=24)
    olaylar = session.exec(
        select(DetectionEvent).where(DetectionEvent.created_at >= esik)
    ).all()
    return [_detection_public_ile_geri_bildirim(session, olay) for olay in olaylar]


@router.post(
    "/{detection_id}/geri-bildirim",
    response_model=FeltReportPublic,
    summary="'Hissettim mi?' geri bildirimi gonder",
)
def gonder_geri_bildirim(
    *,
    detection_id: int,
    geri_bildirim: FeltReportCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(aktif_kullanici),
):
    olay = session.get(DetectionEvent, detection_id)
    if not olay:
        raise HTTPException(status_code=404, detail="Tespit bulunamadi")

    # Kullanici basina TEK kayit: daha once oy verdiyse GUNCELLENIR (cift oy DetectionEvent
    # istatistigini carpitmasin — bkz. _detection_public_ile_geri_bildirim).
    mevcut = session.exec(
        select(FeltReport).where(
            FeltReport.detection_event_id == detection_id,
            FeltReport.user_id == current_user.id,
        )
    ).first()
    if mevcut:
        mevcut.hissetti_mi = geri_bildirim.hissetti_mi
        mevcut.siddet = geri_bildirim.siddet
        mevcut.created_at = datetime.utcnow()
        db_rapor = mevcut
    else:
        db_rapor = FeltReport(
            detection_event_id=detection_id,
            user_id=current_user.id,
            **geri_bildirim.model_dump(),
        )
    session.add(db_rapor)
    session.commit()
    session.refresh(db_rapor)
    return db_rapor


@router.get("/", response_model=list[DetectionEventPublic], summary="Tespit edilen olaylari listele")
def get_detections(
    *,
    session: Session = Depends(get_session),
    admin: User = Depends(admin_gerekli),
):
    return session.exec(select(DetectionEvent)).all()


@router.post("/run", response_model=list[DetectionEventPublic], summary="Kumeleme algoritmasini calistir")
def run_detection(
    *,
    session: Session = Depends(get_session),
    admin: User = Depends(admin_gerekli),
):
    return tespit_et_ve_kaydet(session)


@router.post("/dogrula", response_model=list[DetectionEventPublic], summary="Bekleyen tespitleri resmi veriyle dogrula")
def run_dogrula(
    *,
    session: Session = Depends(get_session),
    admin: User = Depends(admin_gerekli),
):
    dogrulananlar = tespitleri_dogrula(session)
    # Ayni admin akisina, dogrulamadan sonra eskimis pending'leri false_positive
    # isaretleme adimi da eklenir (Asama 1) — ayri bir endpoint gerekmez.
    eskimis_tespitleri_isaretle(session)
    return dogrulananlar


@router.get("/istatistik/", summary="Bolgesel/zamansal tespit istatistikleri (sahte-pozitif analizi)")
def get_istatistik(
    *,
    session: Session = Depends(get_session),
    admin: User = Depends(admin_gerekli),
):
    return _saat_bolge_istatistigi(session)
