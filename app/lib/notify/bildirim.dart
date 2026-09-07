/// Backend'deki NotificationPublic'in Dart karşılığı.
/// GET /user/notifications/ cevabındaki her JSON öğesi bu sınıfa dönüştürülür.
class Bildirim {
  final int id;
  final int? earthquakeId; // dolu ise: resmi/Kandilli bildirimi
  final int? detectionEventId; // dolu ise: crowd (tespit) uyarısı
  final String mesaj; // backend'deki matched_reason
  final DateTime olusturulmaZamani;

  const Bildirim({
    required this.id,
    required this.earthquakeId,
    required this.detectionEventId,
    required this.mesaj,
    required this.olusturulmaZamani,
  });

  /// JSON (Map) -> Bildirim nesnesi. Python'daki **dict açılımının elle hali.
  /// factory = "yeni nesneyi ben kurarım" diyen özel constructor.
  factory Bildirim.fromJson(Map<String, dynamic> json) {
    return Bildirim(
      id: json['id'] as int,
      earthquakeId: json['earthquake_id'] as int?, // null olabilir -> int?
      detectionEventId: json['detection_event_id'] as int?,
      mesaj: json['matched_reason'] as String,
      olusturulmaZamani: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Kart görselini seçmek için türetilmiş bilgi:
  /// true = crowd uyarısı (kırmızı), false = Kandilli teyidi (mavi).
  bool get kaynakCrowdMu => detectionEventId != null;
}

/// FCM push'unun `data` payload'ından (RemoteMessage.data) full-screen alarm
/// ekranını (EarthquakeAlertScreen) tetiklemek için gereken alanları çıkarır.
///
/// Backend (FastAPI) kritik bir depremde şu data payload'ını göndermeli:
/// ```json
/// {
///   "type": "earthquake_alert",
///   "magnitude": "6.1",
///   "distance_km": "20"
/// }
/// ```
/// `notification` alanı (title/body) sistem bildirim çubuğu içindir; full-screen
/// ekranı SADECE `data` alanındaki bu anahtarlar tetikler.
///
/// Not: mesafe km cinsindendir — uygulamanın geri kalanı (map_screen.dart,
/// deprem.dart) da her yerde km kullanıyor, tutarlılık için burada da km.
class PushDepremUyarisi {
  final double magnitude;
  final double distanceKm;

  const PushDepremUyarisi({
    required this.magnitude,
    required this.distanceKm,
  });

  static const _tetikleyiciTip = 'earthquake_alert';

  /// data['type'] == 'earthquake_alert' değilse ya da sayısal alanlar
  /// parse edilemiyorsa null döner (ör. normal bildirim-listesi push'u).
  static PushDepremUyarisi? fromFcmData(Map<String, dynamic> data) {
    if (data['type'] != _tetikleyiciTip) return null;

    final magnitude = double.tryParse(data['magnitude']?.toString() ?? '');
    final distanceKm = double.tryParse(data['distance_km']?.toString() ?? '');
    if (magnitude == null || distanceKm == null) return null;

    return PushDepremUyarisi(magnitude: magnitude, distanceKm: distanceKm);
  }
}
