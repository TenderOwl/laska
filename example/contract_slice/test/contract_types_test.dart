import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('the types of a contract', () {
    const subscription = Subscription(
      plan: SubscriptionPlan(name: 'pro', seats: 5),
      state: SubscriptionState.subscriptionStatePaused,
      features: <String, bool>{'sso': true, 'audit': false},
      payment: SubscriptionPaymentIban('DE00'),
    );

    test('a nested message and a nested enum keep their names', () {
      expect(subscription.plan.name, 'pro');
      expect(subscription.plan.seats, 5);
      expect(subscription.state, SubscriptionState.subscriptionStatePaused);
    });

    test('the JSON of a map is an object', () {
      final json = subscription.toJson();

      expect(json['features'], <String, bool>{'sso': true, 'audit': false});
      expect(json['plan'], <String, dynamic>{'name': 'pro', 'seats': 5});
      expect(json['state'], 'SUBSCRIPTION_STATE_PAUSED');
    });

    test('the JSON of a oneof holds the member that is set', () {
      final json = subscription.toJson();

      expect(json['iban'], 'DE00');
      expect(json.containsKey('cardToken'), isFalse);
    });

    test('a message is read back out of its JSON', () {
      final read = Subscription.fromJson(subscription.toJson());

      expect(read.plan.name, 'pro');
      expect(read.state, SubscriptionState.subscriptionStatePaused);
      expect(read.features, <String, bool>{'sso': true, 'audit': false});
      expect(read.payment, isA<SubscriptionPaymentIban>());
      expect((read.payment! as SubscriptionPaymentIban).value, 'DE00');
    });

    test('a message is read back out of its bytes', () {
      final read = Subscription.fromProtoBytes(subscription.toProtoBytes());

      expect(read.plan.name, 'pro');
      expect(read.plan.seats, 5);
      expect(read.state, SubscriptionState.subscriptionStatePaused);
      expect(read.features, <String, bool>{'sso': true, 'audit': false});
      expect(read.payment, isA<SubscriptionPaymentIban>());
      expect((read.payment! as SubscriptionPaymentIban).value, 'DE00');
    });

    test('the other member of a oneof is read back as well', () {
      const byCard = Subscription(
        plan: SubscriptionPlan(name: 'free', seats: 1),
        state: SubscriptionState.subscriptionStateActive,
        features: <String, bool>{},
        payment: SubscriptionPaymentCardToken('tok_1'),
      );

      final read = Subscription.fromProtoBytes(byCard.toProtoBytes());

      expect(read.payment, isA<SubscriptionPaymentCardToken>());
      expect((read.payment! as SubscriptionPaymentCardToken).value, 'tok_1');
      expect(read.features, isEmpty);
    });

    test('a well-known type keeps the JSON and the bytes of protobuf', () {
      const createdAt = ProtoTimestamp(seconds: 1767225600);

      const user = User(
        id: 'u_1',
        email: 'ada@example.com',
        displayName: 'Ada Lovelace',
        role: UserRole.userRoleAdmin,
        tags: <String>[],
        createdAt: createdAt,
      );

      expect(user.toJson()['createdAt'], '2026-01-01T00:00:00Z');

      final read = User.fromJson(user.toJson());

      expect(read.createdAt, createdAt);
      expect(read.createdAt.toDateTime(), DateTime.utc(2026, 1, 1));

      final fromBytes = User.fromProtoBytes(user.toProtoBytes());

      expect(fromBytes.createdAt, createdAt);
    });
  });
}
