import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'deprem.dart';
import 'tespit.dart';
import '../core/api_client.dart';

/// Harita ekranı (Faz 5).
/// Katmanlar: OSM karoları -> tespit daireleri -> deprem işaretçileri -> kullanıcı.
class MapScreen extends StatefulWidget {
  /// Ana ekrandan gelirken kullanıcının konumu (varsa) — harita oradan açılır.
  final LatLng? baslangicKonumu;

  /// Bildirim kartından gelindiyse: odaklanılacak tespit/deprem id'si.
  final int? odakTespitId;
  final int? odakDepremId;

  const MapScreen({
    super.key,
    this.baslangicKonumu,
    this.odakTespitId,
    this.odakDepremId,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _turkiyeMerkezi = LatLng(39.0, 35.0);

  final _api = ApiClient();
  // Programatik zoom/kaydirma icin haritanin kumandasi (emulator zoom butonlari).
  final _haritaKumandasi = MapController();

  List<Tespit> _tespitler = [];
  List<Deprem> _depremler = [];
  String? _hata;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    try {
      final tespitler = await _api.aktifTespitleriGetir();
      final depremler = await _api.depremleriGetir();
      if (!mounted) return;
      setState(() {
        _tespitler = tespitler;
        _depremler = depremler;
        _hata = null;
      });
      _odaklan(); // bildirim kartindan gelindiyse ilgili noktaya git
    } catch (hata) {
      if (!mounted) return;
      setState(() => _hata = hata.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Bildirim kartindan gelinen tespit/depremi haritada bulup kamerayi oraya tasir.
  void _odaklan() {
    LatLng? hedef;
    if (widget.odakTespitId != null) {
      for (final t in _tespitler) {
        if (t.id == widget.odakTespitId) hedef = LatLng(t.merkezLat, t.merkezLon);
      }
    }
    if (hedef == null && widget.odakDepremId != null) {
      for (final d in _depremler) {
        if (d.id == widget.odakDepremId) hedef = LatLng(d.lat, d.lon);
      }
    }
    if (hedef != null) {
      _haritaKumandasi.move(hedef, 11);
    } else if (widget.odakTespitId != null || widget.odakDepremId != null) {
      // Kayit artik listede yok (orn. 24 saatten eski tespit) — kullaniciyi bilgilendir.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu bildirimin kaydı haritada bulunamadı (eski olabilir)')),
      );
    }
  }

  void _zoomDegistir(double fark) {
    final kamera = _haritaKumandasi.camera;
    _haritaKumandasi.move(kamera.center, kamera.zoom + fark);
  }

  /// Tum veriyi (tespitler + depremler + kullanici) tek bakista kapsayacak
  /// sekilde kamerayi ayarlar ("tumunu kapsa").
  void _tumunuKapsa() {
    final noktalar = <LatLng>[
      for (final t in _tespitler) LatLng(t.merkezLat, t.merkezLon),
      for (final d in _depremler) LatLng(d.lat, d.lon),
      if (widget.baslangicKonumu != null) widget.baslangicKonumu!,
    ];
    if (noktalar.isEmpty) return;
    _haritaKumandasi.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(noktalar),
        padding: const EdgeInsets.all(56), // kenarlara yapismasin
      ),
    );
  }

  /// Tespit dairesinin rengi/opakligini "Hissettim mi?" ortalama siddetine gore ayarlar
  /// (Asama 6) — oy yoksa eski sabit gorunume (0.35 alfa) duser.
  Color _tespitDolguRengi(Tespit t) {
    final temel = t.dogrulandiMi ? Colors.red : Colors.red.shade200;
    final alfa = t.ortalamaSiddet == null
        ? 0.35
        : (0.2 + (t.ortalamaSiddet! / 5) * 0.4).clamp(0.2, 0.6);
    return temel.withValues(alpha: alfa);
  }

  void _geriBildirimGoster(Tespit t) {
    bool hissettiMi = true;
    int siddet = 3;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Hissettin mi?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bu bölgede ${t.raporSayisi} kişi rapor gönderdi.'),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Evet, hissettim')),
                      ButtonSegment(value: false, label: Text('Hayır')),
                    ],
                    selected: {hissettiMi},
                    onSelectionChanged: (secim) =>
                        setDialogState(() => hissettiMi = secim.first),
                  ),
                  const SizedBox(height: 12),
                  Text('Şiddet: $siddet / 5'),
                  Slider(
                    value: siddet.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$siddet',
                    onChanged: (deger) =>
                        setDialogState(() => siddet = deger.round()),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    try {
                      await _api.gonderGeriBildirim(t.id, hissettiMi, siddet);
                      await _verileriYukle();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Geri bildiriminiz gönderildi')),
                      );
                    } catch (hata) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(hata.toString().replaceFirst('Exception: ', ''))),
                      );
                    }
                  },
                  child: const Text('Gönder'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _depremDetayGoster(Deprem d) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min, // icerik kadar yer kapla
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d.yerAdi ?? 'Bilinmeyen konum',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Büyüklük: M${d.buyukluk.toStringAsFixed(1)}'),
            Text('Derinlik: ${d.derinlikKm.toStringAsFixed(1)} km'),
            Text('Zaman: ${d.zaman.toLocal()}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deprem Haritası'),
        actions: [
          IconButton(
            onPressed: _verileriYukle,
            icon: const Icon(Icons.refresh),
            tooltip: 'Verileri yenile',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _haritaKumandasi,
            options: MapOptions(
              initialCenter: widget.baslangicKonumu ?? _turkiyeMerkezi,
              initialZoom: widget.baslangicKonumu != null ? 10 : 6,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kaan.deprem_app',
              ),
              // ETKI ALANI: kullanicinin bildirim yaricapi (100 km) — bu dairenin
              // ICINDEKI olaylar bildirim uretir, disindakiler sadece haritada bilgi.
              if (widget.baslangicKonumu != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: widget.baslangicKonumu!,
                      radius: 100000, // 100 km = backend pref_radius_km varsayilani
                      useRadiusInMeter: true,
                      color: Colors.blue.withValues(alpha: 0.06),
                      borderColor: Colors.blue.withValues(alpha: 0.5),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              // Tespit daireleri: yaricap gercek 2 km (tespit yaricapi) —
              // zoom yaptikca daire de buyur/kuculur (useRadiusInMeter).
              CircleLayer(
                circles: [
                  for (final t in _tespitler)
                    CircleMarker(
                      point: LatLng(t.merkezLat, t.merkezLon),
                      radius: 2000,
                      useRadiusInMeter: true,
                      color: _tespitDolguRengi(t),
                      borderColor: t.dogrulandiMi ? Colors.red.shade900 : Colors.red,
                      borderStrokeWidth: 2,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Tespit dairelerine dokununca "Hissettin mi?" diyalogu (Asama 6) —
                  // CircleLayer'in kendisi tiklanamadigi icin ustune sabit boyutlu,
                  // gorunmez bir dokunma alani ekliyoruz (deprem isaretcileriyle ayni desen).
                  for (final t in _tespitler)
                    Marker(
                      point: LatLng(t.merkezLat, t.merkezLon),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        // behavior: opaque olmadan SizedBox.expand() SEFFAF oldugu icin
                        // hit-test'i GECMEZ (Flutter'in varsayilan deferToChild davranisi) —
                        // dokunma alani gorunmez olsa bile taplari YAKALAMASI gerekiyor.
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _geriBildirimGoster(t),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  // Resmi depremler: turuncu isaretci, buyukluge gore boy.
                  for (final d in _depremler)
                    Marker(
                      point: LatLng(d.lat, d.lon),
                      width: 24 + d.buyukluk * 4,
                      height: 24 + d.buyukluk * 4,
                      child: GestureDetector(
                        onTap: () => _depremDetayGoster(d),
                        child: Icon(
                          Icons.location_on,
                          color: Colors.orange.shade800,
                          size: 24 + d.buyukluk * 4,
                        ),
                      ),
                    ),
                  // Kullanicinin kendi konumu: mavi nokta.
                  if (widget.baslangicKonumu != null)
                    Marker(
                      point: widget.baslangicKonumu!,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap katkıda bulunanlar'),
              ),
            ],
          ),
          // Emulatorde iki parmak zoom zor -> +/- butonlari (kullanici istegi).
          Positioned(
            right: 12,
            bottom: 32,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'fitAll',
                  onPressed: _tumunuKapsa,
                  tooltip: 'Tümünü kapsa',
                  child: const Icon(Icons.fit_screen),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoomIn',
                  onPressed: () => _zoomDegistir(1),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoomOut',
                  onPressed: () => _zoomDegistir(-1),
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
          if (_hata != null)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Card(
                color: Colors.red.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_hata!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
