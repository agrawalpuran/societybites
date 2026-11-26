import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/partner_delivery.dart';

void main() {
  test('finding a rider is the first step', () {
    const delivery = PartnerDelivery(state: 'booked');
    expect(delivery.progressIndex, 0);
    expect(delivery.progressSteps.first.kind, PartnerProgressKind.current);
    expect(delivery.progressSteps.last.kind, PartnerProgressKind.upcoming);
  });

  test('picked up marks en route current', () {
    const delivery = PartnerDelivery(state: 'picked_up');
    expect(delivery.stateLabel, 'On the way');
    expect(delivery.progressSteps[2].label, 'En route');
    expect(delivery.progressSteps[2].kind, PartnerProgressKind.current);
    expect(delivery.progressSteps[1].kind, PartnerProgressKind.done);
  });

  test('delivered completes every step', () {
    const delivery = PartnerDelivery(state: 'delivered');
    expect(
      delivery.progressSteps.every((step) => step.kind == PartnerProgressKind.done),
      isTrue,
    );
  });

  test('retrying shows trying another rider', () {
    const delivery = PartnerDelivery(state: 'retrying');
    expect(delivery.stateLabel, 'Trying another rider');
    expect(delivery.isWaitingForRider, isTrue);
    expect(delivery.progressIndex, 0);
  });

  test('failed trips hide the progress track', () {
    const delivery = PartnerDelivery(state: 'failed');
    expect(delivery.showsProgress, isFalse);
    expect(delivery.progressSteps, isEmpty);
  });
}
