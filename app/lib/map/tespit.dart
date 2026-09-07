/// Backend'deki DetectionEventPublic'in Dart karşılığı (harita için).
class Tespit {
  final int id;
  final double merkezLat;
  final double merkezLon;
  final double? tahminiSiddet;
  final int raporSayisi;
  final String durum; // pending / confirmed / false_positive
  final DateTime olusturulmaZamani;
  // "Hissettim mi?" ozeti (Asama 6) — backend'de her istekte FeltReport'lardan hesaplanir.
  final int oySayisi;
  final double? ortalamaSiddet;

  const Tespit({
    required this.id,
    required this.merkezLat,
    required this.merkezLon,
    required this.tahminiSiddet,
    required this.raporSayisi,
    required this.durum,
    required this.olusturulmaZamani,
    required this.oySayisi,
    required this.ortalamaSiddet,
  });

  factory Tespit.fromJson(Map<String, dynamic> json) {
    return Tespit(
      id: json['id'] as int,
      // JSON sayilari int gelebilir -> num uzerinden guvenli double'a cevir
      merkezLat: (json['center_lat'] as num).toDouble(),
      merkezLon: (json['center_lon'] as num).toDouble(),
      tahminiSiddet: (json['estimated_magnitude'] as num?)?.toDouble(),
      raporSayisi: json['report_count'] as int,
      durum: json['status'] as String,
      olusturulmaZamani: DateTime.parse(json['created_at'] as String),
      oySayisi: json['oy_sayisi'] as int? ?? 0,
      ortalamaSiddet: (json['ortalama_siddet'] as num?)?.toDouble(),
    );
  }

  bool get dogrulandiMi => durum == 'confirmed';
}
