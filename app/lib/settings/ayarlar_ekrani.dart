import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../location/konum_servisi.dart';
import '../tremor/sarsinti_servisi.dart';
import 'ek_konum.dart';
import 'konum_secici_ekrani.dart';

/// Bildirim tercihleri ekrani: kullanicinin "yaricap" (hangi mesafedeki
/// depremlerden haberdar olsun) ve "minimum buyukluk" (hangi siddetin
/// altini onemsemesin) esiklerini ayarlamasini saglar.
///
/// Bu iki alan (pref_radius_km, pref_min_magnitude) doluysa backend
/// eslestirmesi (depreme_uygun_kullanicilari_bul, olay_icin_kullanicilari_bul)
/// kullaniciyi bulabiliyor — bos kalirsa hicbir bildirim/push GELMIYOR.
class AyarlarEkrani extends StatefulWidget {
  const AyarlarEkrani({super.key});

  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  final _api = ApiClient();
  final _konumServisi = KonumServisi();

  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  String? _hataMesaji;

  double _yaricapKm = 100;
  double _minBuyukluk = 3.0;

  // --- Bildirim konumu: GPS (otomatik) veya haritadan secilmis sabit konum ---
  String _konumModu = konumModuGps;
  double? _konumLat;
  double? _konumLon;
  bool _konumIsleniyor = false; // GPS senkronu / harita secimi surerken

  // --- Ek konumlar (ev/isyeri gibi, birincil konumdan bagimsiz) ---
  List<EkKonum> _ekKonumlar = [];
  bool _ekKonumlarYukleniyor = true;
  bool _ekKonumIsleniyor = false; // ekleme/silme surerken

  // --- Arka plan izleme anahtari (eskiden home_screen.dart'taydi) ---
  final _kasa = const FlutterSecureStorage();
  bool _arkaPlanIzlemeAktif = false;

  @override
  void initState() {
    super.initState();
    _tercihleriYukle();
    _arkaPlanIzlemeDurumunuYukle();
    _konumModunuYukle();
    _ekKonumlariYukle();
  }

  Future<void> _ekKonumlariYukle() async {
    try {
      final konumlar = await _api.ekKonumlariGetir();
      if (!mounted) return;
      setState(() {
        _ekKonumlar = konumlar;
        _ekKonumlarYukleniyor = false;
      });
    } catch (_) {
      // Sessiz gec: bu liste bos gorunse de sayfanin geri kalani calismaya devam etsin.
      if (!mounted) return;
      setState(() => _ekKonumlarYukleniyor = false);
    }
  }

  Future<void> _ekKonumEkle() async {
    final secilen = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const KonumSeciciEkrani()),
    );
    if (secilen == null || !mounted) return;

    final sonuc = await _ekKonumDialoguGoster();
    if (sonuc == null || !mounted) return;

    setState(() => _ekKonumIsleniyor = true);
    try {
      await _api.ekKonumEkle(
        etiket: sonuc.$1,
        latitude: secilen.latitude,
        longitude: secilen.longitude,
        radiusKm: sonuc.$2,
        minMagnitude: sonuc.$3,
      );
      await _ekKonumlariYukle();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${sonuc.$1}" eklendi')),
      );
    } catch (hata) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hata.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _ekKonumIsleniyor = false);
    }
  }

  /// Etiket + yaricap + min buyukluk sorar. Iptal edilirse null doner.
  Future<(String, double, double)?> _ekKonumDialoguGoster() async {
    final etiketController = TextEditingController();
    double yaricapKm = 100;
    double minBuyukluk = 3.0;

    return showDialog<(String, double, double)>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Ek Konum Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: etiketController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Etiket',
                        hintText: 'ör. Ev, İşyeri',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Yarıçap: ${yaricapKm.toStringAsFixed(0)} km'),
                    Slider(
                      value: yaricapKm,
                      min: 0,
                      max: 1000,
                      divisions: 100,
                      label: '${yaricapKm.toStringAsFixed(0)} km',
                      onChanged: (deger) => setDialogState(() => yaricapKm = deger),
                    ),
                    Text('Minimum büyüklük: M${minBuyukluk.toStringAsFixed(1)}'),
                    Slider(
                      value: minBuyukluk,
                      min: 0,
                      max: 10,
                      divisions: 100,
                      label: 'M${minBuyukluk.toStringAsFixed(1)}',
                      onChanged: (deger) => setDialogState(() => minBuyukluk = deger),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () {
                    final etiket = etiketController.text.trim();
                    if (etiket.isEmpty) return;
                    Navigator.of(dialogContext).pop((etiket, yaricapKm, minBuyukluk));
                  },
                  child: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _ekKonumSil(EkKonum konum) async {
    setState(() => _ekKonumIsleniyor = true);
    try {
      await _api.ekKonumSil(konum.id);
      await _ekKonumlariYukle();
    } catch (hata) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hata.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _ekKonumIsleniyor = false);
    }
  }

  Future<void> _konumModunuYukle() async {
    final deger = await _kasa.read(key: konumModuAnahtari);
    if (!mounted) return;
    setState(() => _konumModu = deger == konumModuManuel ? konumModuManuel : konumModuGps);
  }

  /// Moda gecince (GPS <-> Manuel) HEMEN etkili olsun diye burada da senkronluyoruz —
  /// GPS'e gecerken cihazin guncel konumunu alip backend'e yazariz (bir sonraki
  /// uygulama acilisini beklemeye gerek yok); manuele gecerken sadece modu
  /// degistiririz, kullanici "Haritadan seç" ile konumu belirler.
  Future<void> _konumModunuDegistir(String yeniMod) async {
    setState(() => _konumModu = yeniMod);
    await _kasa.write(key: konumModuAnahtari, value: yeniMod);

    if (yeniMod == konumModuGps) {
      setState(() => _konumIsleniyor = true);
      try {
        final konum = await _konumServisi.konumAl();
        await _api.konumTercihiGuncelle(konum.latitude, konum.longitude);
        if (!mounted) return;
        setState(() {
          _konumLat = konum.latitude;
          _konumLon = konum.longitude;
        });
      } catch (hata) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hata.toString().replaceFirst('Exception: ', ''))),
        );
      } finally {
        if (mounted) setState(() => _konumIsleniyor = false);
      }
    }
  }

  Future<void> _haritadanSec() async {
    final baslangic = _konumLat != null && _konumLon != null
        ? LatLng(_konumLat!, _konumLon!)
        : null;
    final secilen = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => KonumSeciciEkrani(baslangicKonumu: baslangic),
      ),
    );
    if (secilen == null || !mounted) return;

    setState(() => _konumIsleniyor = true);
    try {
      await _api.konumTercihiGuncelle(secilen.latitude, secilen.longitude);
      // Haritadan sec = "manuel" moda gecmek demek — GPS bunun ustune yazmasin.
      await _kasa.write(key: konumModuAnahtari, value: konumModuManuel);
      if (!mounted) return;
      setState(() {
        _konumModu = konumModuManuel;
        _konumLat = secilen.latitude;
        _konumLon = secilen.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum güncellendi')),
      );
    } catch (hata) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hata.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _konumIsleniyor = false);
    }
  }

  Future<void> _arkaPlanIzlemeDurumunuYukle() async {
    final deger = await _kasa.read(key: arkaPlanTercihAnahtari);
    if (!mounted) return;
    setState(() => _arkaPlanIzlemeAktif = deger == 'true');
  }

  /// Anahtar degistiginde: servisi baslat/durdur + tercihi kasaya yaz (bir
  /// sonraki acilista home_screen.dart bunu okuyup servisi geri yukler).
  Future<void> _arkaPlanIzlemeAnahtariDegisti(bool deger) async {
    setState(() => _arkaPlanIzlemeAktif = deger);
    if (deger) {
      await sarsintiServisiniBaslat();
    } else {
      await sarsintiServisiniDurdur();
    }
    await _kasa.write(key: arkaPlanTercihAnahtari, value: deger.toString());
  }

  Future<void> _tercihleriYukle() async {
    try {
      final kullanici = await _api.meGetir();
      if (!mounted) return;
      setState(() {
        // Kullanici hic ayar yapmamissa (deger null) makul varsayilanlarla basla.
        _yaricapKm = (kullanici['pref_radius_km'] as num?)?.toDouble() ?? 100;
        _minBuyukluk = (kullanici['pref_min_magnitude'] as num?)?.toDouble() ?? 3.0;
        _konumLat = (kullanici['pref_latitude'] as num?)?.toDouble();
        _konumLon = (kullanici['pref_longitude'] as num?)?.toDouble();
        _yukleniyor = false;
      });
    } catch (hata) {
      if (!mounted) return;
      setState(() {
        _hataMesaji = hata.toString().replaceFirst('Exception: ', '');
        _yukleniyor = false;
      });
    }
  }

  Future<void> _kaydet() async {
    setState(() => _kaydediliyor = true);
    try {
      await _api.bildirimTercihleriniGuncelle(
        radiusKm: _yaricapKm,
        minMagnitude: _minBuyukluk,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim tercihleri kaydedildi')),
      );
    } catch (hata) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hata.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirim Ayarları')),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : _hataMesaji != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_hataMesaji!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Bildirim konumu',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Yarıçap buradan ölçülür. GPS ile cihazının konumu otomatik '
                      'senkronlanır, ya da ev/işyeri gibi sabit bir konum seçebilirsin.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: konumModuGps,
                          label: Text('GPS (otomatik)'),
                          icon: Icon(Icons.gps_fixed),
                        ),
                        ButtonSegment(
                          value: konumModuManuel,
                          label: Text('Sabit konum'),
                          icon: Icon(Icons.push_pin_outlined),
                        ),
                      ],
                      selected: {_konumModu},
                      onSelectionChanged: _konumIsleniyor
                          ? null
                          : (secim) => _konumModunuDegistir(secim.first),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _konumLat != null && _konumLon != null
                                ? '${_konumLat!.toStringAsFixed(4)}, ${_konumLon!.toStringAsFixed(4)}'
                                : 'Kayıtlı konum yok',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                        if (_konumIsleniyor)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _konumIsleniyor ? null : _haritadanSec,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Haritadan seç'),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 20),
                    Text(
                      'Bildirim yarıçapı: ${_yaricapKm.toStringAsFixed(0)} km',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Bu mesafe içinde gerçekleşen (ya da tespit edilen) depremler '
                      'için bildirim alırsın.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Slider(
                      value: _yaricapKm,
                      min: 0,
                      max: 1000,
                      divisions: 100,
                      label: '${_yaricapKm.toStringAsFixed(0)} km',
                      onChanged: (deger) => setState(() => _yaricapKm = deger),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Minimum büyüklük: M${_minBuyukluk.toStringAsFixed(1)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Bu değerin altındaki depremler için bildirim gelmez.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Slider(
                      value: _minBuyukluk,
                      min: 0,
                      max: 10,
                      divisions: 100,
                      label: 'M${_minBuyukluk.toStringAsFixed(1)}',
                      onChanged: (deger) => setState(() => _minBuyukluk = deger),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _kaydediliyor ? null : _kaydet,
                        child: _kaydediliyor
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Kaydet'),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 20),
                    Text(
                      'Ek Konumlar',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'GPS/sabit konumundan bağımsız — ev, işyeri gibi ek noktalar '
                      'ekleyip oralara yakın depremler için de ayrıca haberdar olabilirsin.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    if (_ekKonumlarYukleniyor)
                      const Center(child: CircularProgressIndicator())
                    else if (_ekKonumlar.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Henüz ek konum eklenmedi.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      for (final konum in _ekKonumlar)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.home_outlined),
                            title: Text(konum.etiket),
                            subtitle: Text(
                              '${konum.latitude.toStringAsFixed(4)}, '
                              '${konum.longitude.toStringAsFixed(4)} • '
                              '${konum.radiusKm.toStringAsFixed(0)} km • '
                              'M${konum.minMagnitude.toStringAsFixed(1)}+',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              onPressed: _ekKonumIsleniyor ? null : () => _ekKonumSil(konum),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Sil',
                            ),
                          ),
                        ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _ekKonumIsleniyor ? null : _ekKonumEkle,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Ek konum ekle'),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 8),
                    // Acikken Android kalici bir bildirim gostermek ZORUNDA
                    // (sistem kisidi, gizlenemez) — bkz. tremor/sarsinti_servisi.dart.
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Arka planda deprem izlemeyi etkinleştir'),
                      subtitle: const Text(
                        'Açıkken telefon kapalıyken de titreşim algılayıp otomatik '
                        'rapor gönderir (bildirim çubuğunda görünür).',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _arkaPlanIzlemeAktif,
                      onChanged: _arkaPlanIzlemeAnahtariDegisti,
                    ),
                  ],
                ),
    );
  }
}
