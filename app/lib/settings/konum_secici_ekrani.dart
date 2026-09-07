import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../location/konum_servisi.dart';

/// Kullanicinin bildirim konumunu HARITADAN secmesini saglar — ev/isyeri gibi
/// sabit bir konum, GPS'e bagli kalmadan belirlenebilsin diye.
///
/// UX: klasik "haritayi kaydir, isaretci ortada sabit dursun" deseni (Uber/
/// Google Maps konum secicileriyle ayni) — tek tek tiklamaktan daha az hataya
/// acik, cunku isaretcinin TAM ORTADA oldugu her zaman net.
///
/// Geri donus: kullanici "Bu konumu kullan"a basarsa secilen LatLng ile
/// Navigator.pop yapar; vazgecerse null (geri tusu/AppBar back).
class KonumSeciciEkrani extends StatefulWidget {
  const KonumSeciciEkrani({super.key, this.baslangicKonumu});

  final LatLng? baslangicKonumu;

  @override
  State<KonumSeciciEkrani> createState() => _KonumSeciciEkraniState();
}

class _KonumSeciciEkraniState extends State<KonumSeciciEkrani> {
  static const _turkiyeMerkezi = LatLng(39.0, 35.0);

  final _haritaKumandasi = MapController();
  final _konumServisi = KonumServisi();
  bool _gpsAliniyor = false;

  Future<void> _gpsKonumunaGit() async {
    setState(() => _gpsAliniyor = true);
    try {
      final konum = await _konumServisi.konumAl();
      if (!mounted) return;
      _haritaKumandasi.move(LatLng(konum.latitude, konum.longitude), 14);
    } catch (hata) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hata.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _gpsAliniyor = false);
    }
  }

  void _konumuOnayla() {
    Navigator.of(context).pop(_haritaKumandasi.camera.center);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konum Seç'),
        actions: [
          IconButton(
            onPressed: _gpsAliniyor ? null : _gpsKonumunaGit,
            icon: _gpsAliniyor
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.my_location),
            tooltip: 'Şu anki GPS konumuma git',
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            mapController: _haritaKumandasi,
            options: MapOptions(
              initialCenter: widget.baslangicKonumu ?? _turkiyeMerkezi,
              initialZoom: widget.baslangicKonumu != null ? 13 : 6,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kaan.deprem_app',
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap katkıda bulunanlar'),
              ),
            ],
          ),
          // Haritanin TAM ORTASINDA sabit isaretci — kullanici haritayi kaydirir,
          // isaretci hep merkezde kalir. Alt ucu tam merkez noktasini gostersin
          // diye dikeyde yukari kaydirilmis (Icon'un "sivri ucu" alt-orta noktada).
          const Padding(
            padding: EdgeInsets.only(bottom: 40),
            child: Icon(Icons.location_pin, size: 48, color: Colors.red),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _konumuOnayla,
                child: const Text('Bu konumu kullan'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
