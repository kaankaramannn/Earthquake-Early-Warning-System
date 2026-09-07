import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// ANN sınıflandırıcısı (Aşama 7) için GEÇİCİ veri toplama ekranı.
///
/// Normal algılama/rapor akışına HİÇ dokunmaz — kendi ivmeölçer dinleyicisini
/// ana isolate'te (arka plan servisinden bağımsız) açar, sadece etiketli ham
/// örnekleri (x, y, z, zaman) yerel bir CSV dosyasına yazar. Veri toplama işi
/// bitince bu ekran (ve bu dosya) koddan tamamen kaldırılabilir.
class VeriToplamaEkrani extends StatefulWidget {
  const VeriToplamaEkrani({super.key});

  @override
  State<VeriToplamaEkrani> createState() => _VeriToplamaEkraniState();
}

/// Aşama 7 planında karar verilen dört senaryo — negatif sınıf (masada durgun
/// hariç, o füzyonun TABANI olarak kullanılacak, bkz. plan 7.3).
enum _Senaryo {
  masadaDurgun('masada_durgun', 'Masada durgun (referans)'),
  cepteYurumeKosma('cepte_yurume_kosma', 'Cepte yürüme/koşma'),
  aracta('aracta', 'Araçta'),
  eldeHareket('elde_hareket', 'Elde rastgele hareket');

  final String dosyaEtiketi;
  final String gorunenAd;
  const _Senaryo(this.dosyaEtiketi, this.gorunenAd);
}

class _HamOrnek {
  final int tMs; // kayit baslangicindan bu yana gecen milisaniye
  final double x, y, z;
  const _HamOrnek(this.tMs, this.x, this.y, this.z);
}

class _VeriToplamaEkraniState extends State<VeriToplamaEkrani> {
  _Senaryo _seciliSenaryo = _Senaryo.masadaDurgun;
  StreamSubscription<AccelerometerEvent>? _ivmeAboneligi;

  final List<_HamOrnek> _tampon = [];
  DateTime? _kayitBaslangici;
  Timer? _sureGuncelleyici;
  Duration _gecenSure = Duration.zero;

  bool get _kayitAktif => _ivmeAboneligi != null;

  @override
  void dispose() {
    _ivmeAboneligi?.cancel();
    _sureGuncelleyici?.cancel();
    super.dispose();
  }

  void _kayidiBaslat() {
    _tampon.clear();
    _kayitBaslangici = DateTime.now();
    _ivmeAboneligi = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // sarsinti_servisi.dart ile AYNI hiz
    ).listen((olay) {
      final tMs = DateTime.now().difference(_kayitBaslangici!).inMilliseconds;
      _tampon.add(_HamOrnek(tMs, olay.x, olay.y, olay.z));
    });
    _sureGuncelleyici = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _gecenSure = DateTime.now().difference(_kayitBaslangici!));
    });
    setState(() {});
  }

  Future<void> _kayidiDurdurVeKaydet() async {
    await _ivmeAboneligi?.cancel();
    _ivmeAboneligi = null;
    _sureGuncelleyici?.cancel();
    _sureGuncelleyici = null;

    final ornekSayisi = _tampon.length;
    if (ornekSayisi == 0) {
      setState(() {});
      return;
    }

    try {
      final dosya = await _dosyayaYaz(_seciliSenaryo, _tampon);
      if (!mounted) return;
      setState(() => _gecenSure = Duration.zero);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$ornekSayisi örnek kaydedildi: ${dosya.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (hata) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıt yazılamadı: $hata')),
      );
    }
  }

  /// CSV'yi cihazın harici uygulama dizinine yazar (Android'de
  /// `/storage/emulated/0/Android/data/<paket>/files/`) — kök izin gerekmeden
  /// `adb pull` ile bilgisayara alınabilir.
  Future<File> _dosyayaYaz(_Senaryo senaryo, List<_HamOrnek> ornekler) async {
    final dizin = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final zamanEtiketi = _dosyaIcinZaman(DateTime.now());
    final dosya = File('${dizin.path}/${senaryo.dosyaEtiketi}_$zamanEtiketi.csv');

    final tampon = StringBuffer('t_ms,x,y,z\n');
    for (final o in ornekler) {
      tampon.writeln('${o.tMs},${o.x},${o.y},${o.z}');
    }
    return dosya.writeAsString(tampon.toString());
  }

  String _dosyaIcinZaman(DateTime z) {
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${z.year}${iki(z.month)}${iki(z.day)}_${iki(z.hour)}${iki(z.minute)}${iki(z.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Veri Toplama (Aşama 7)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Bu ekran SADECE ANN eğitimi için etiketli ivmeölçer verisi toplar — '
              'deprem algılama/rapor gönderme akışını etkilemez.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<_Senaryo>(
              initialValue: _seciliSenaryo,
              decoration: const InputDecoration(labelText: 'Senaryo', border: OutlineInputBorder()),
              items: _Senaryo.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.gorunenAd)))
                  .toList(),
              onChanged: _kayitAktif ? null : (s) => setState(() => _seciliSenaryo = s!),
            ),
            const SizedBox(height: 24),
            if (_kayitAktif) ...[
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.red, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      '${_gecenSure.inMinutes}:${(_gecenSure.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Text('${_tampon.length} örnek'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _kayidiDurdurVeKaydet,
                icon: const Icon(Icons.stop),
                label: const Text('Durdur ve Kaydet'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
              ),
            ] else
              ElevatedButton.icon(
                onPressed: _kayidiBaslat,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Kaydı Başlat'),
              ),
          ],
        ),
      ),
    );
  }
}
