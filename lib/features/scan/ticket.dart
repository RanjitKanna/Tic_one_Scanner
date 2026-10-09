import 'package:equatable/equatable.dart';

enum TicketType { movie, bus }

class Passenger extends Equatable {
  final String name;
  final int? age;
  final String gender;
  final String seat;

  const Passenger({
    required this.name,
    required this.age,
    required this.gender,
    required this.seat,
  });

  factory Passenger.fromJson(Map<String, dynamic> json) => Passenger(
    name: json['passengerName']?.toString() ?? '',
    age: (json['age'] as num?)?.toInt(),
    gender: json['gender']?.toString() ?? '',
    seat: json['seatNumber']?.toString() ?? '',
  );

  @override
  List<Object?> get props => [name, age, gender, seat];
}

/// A booking as returned by `/api/admin/tickets/:code`.
class Ticket extends Equatable {
  final TicketType type;
  final String bookingCode;
  final String? pnr;
  final String bookingStatus;
  final String paymentStatus;
  final String customerName;
  final String customerPhone;

  /// Show time (movie) or departure (bus), in local time.
  final DateTime startsAt;

  /// Bus arrival, in local time.
  final DateTime? endsAt;

  final String title;
  final String venue;
  final String subVenue;
  final List<String> seats;
  final List<Passenger> passengers;
  final String? boardingPoint;
  final String? boardingTime;
  final DateTime? checkedInAt;
  final String? checkedInBy;

  const Ticket({
    required this.type,
    required this.bookingCode,
    required this.pnr,
    required this.bookingStatus,
    required this.paymentStatus,
    required this.customerName,
    required this.customerPhone,
    required this.startsAt,
    required this.endsAt,
    required this.title,
    required this.venue,
    required this.subVenue,
    required this.seats,
    required this.passengers,
    required this.boardingPoint,
    required this.boardingTime,
    required this.checkedInAt,
    required this.checkedInBy,
  });

  int get admitCount =>
      type == TicketType.movie ? seats.length : passengers.length;

  /// "2 guests", "1 passenger"…
  String get admitLabel {
    final n = admitCount;
    final noun = type == TicketType.movie ? 'guest' : 'passenger';
    return '$n $noun${n == 1 ? '' : 's'}';
  }

  /// Reference to send back to the server for check-in.
  String get reference => bookingCode;

  factory Ticket.fromJson(Map<String, dynamic> json) {
    final isBus = json['type'] == 'bus';
    String str(String key) => json[key]?.toString() ?? '';
    DateTime? time(String key) =>
        DateTime.tryParse(json[key]?.toString() ?? '')?.toLocal();

    if (isBus) {
      final passengers = (json['passengers'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Passenger.fromJson)
          .toList();
      return Ticket(
        type: TicketType.bus,
        bookingCode: str('bookingCode'),
        pnr: json['pnrNumber']?.toString(),
        bookingStatus: str('bookingStatus').toLowerCase(),
        paymentStatus: str('paymentStatus').toLowerCase(),
        customerName: str('userName'),
        customerPhone: json['contactPhone']?.toString() ?? str('userPhone'),
        startsAt: time('departureTime') ?? DateTime.now(),
        endsAt: time('arrivalTime'),
        title: '${str('sourceCity')} → ${str('destinationCity')}',
        venue: str('operatorName'),
        subVenue: [
          str('busName'),
          str('busNumber'),
        ].where((s) => s.isNotEmpty).join(' · '),
        seats: passengers.map((p) => p.seat).toList(),
        passengers: passengers,
        boardingPoint: json['boardingName']?.toString(),
        boardingTime: json['boardingTime']?.toString(),
        checkedInAt: time('checkedInAt'),
        checkedInBy: json['checkedInBy']?.toString(),
      );
    }

    return Ticket(
      type: TicketType.movie,
      bookingCode: str('bookingCode'),
      pnr: null,
      bookingStatus: str('bookingStatus').toLowerCase(),
      paymentStatus: str('paymentStatus').toLowerCase(),
      customerName: str('userName'),
      customerPhone: str('userPhone'),
      startsAt: time('showTime') ?? DateTime.now(),
      endsAt: null,
      title: str('movieTitle'),
      venue: str('theaterName'),
      subVenue: [
        str('screenName'),
        str('movieFormat'),
        str('movieLanguage'),
      ].where((s) => s.isNotEmpty).join(' · '),
      seats: (json['seats'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((s) => s['seatIdentifier']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      passengers: const [],
      boardingPoint: null,
      boardingTime: null,
      checkedInAt: time('checkedInAt'),
      checkedInBy: json['checkedInBy']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    type,
    bookingCode,
    pnr,
    bookingStatus,
    paymentStatus,
    startsAt,
    seats,
    passengers,
    checkedInAt,
    checkedInBy,
  ];
}
