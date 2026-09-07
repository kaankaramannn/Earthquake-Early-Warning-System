/// Backend'deki EarthquakePublic'in Dart karşılığı (harita için).
class Deprem {
  final int id;
  final double buyukluk;
  final double lat;
  final double lon;
  final double derinlikKm;
  final DateTime zaman;
  final String? yerAdi;

  const Deprem({
    required this.id,
    required this.buyukluk,
    required this.lat,
    required this.lon,
    required this.derinlikKm,
    required this.zaman,
    required this.yerAdi,
  });

  factory Deprem.fromJson(Map<String, dynamic> json) {
    return Deprem(
      id: json['id'] as int,
      buyukluk: (json['magnitude'] as num).toDouble(),
      lat: (json['latitude'] as num).toDouble(),
      lon: (json['longitude'] as num).toDouble(),
      derinlikKm: (json['depth_km'] as num).toDouble(),
      zaman: DateTime.parse(json['occurred_at'] as String),
      yerAdi: json['location_name'] as String?,
    );
  }
}
