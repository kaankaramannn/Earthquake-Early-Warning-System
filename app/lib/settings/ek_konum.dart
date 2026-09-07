/// Backend'deki UserLocationPublic'in Dart karsiligi — kullanicinin GPS/manuel
/// birincil konumundan BAGIMSIZ, ayrica takip ettigi ek noktalar (ev, isyeri).
class EkKonum {
  final int id;
  final String etiket;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final double minMagnitude;

  const EkKonum({
    required this.id,
    required this.etiket,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.minMagnitude,
  });

  factory EkKonum.fromJson(Map<String, dynamic> json) {
    return EkKonum(
      id: json['id'] as int,
      etiket: json['etiket'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusKm: (json['radius_km'] as num).toDouble(),
      minMagnitude: (json['min_magnitude'] as num).toDouble(),
    );
  }
}
