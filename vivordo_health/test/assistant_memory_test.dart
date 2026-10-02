import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/assistant_memory_screen.dart';

void main() {
  test('forgetting a fact also forgets the summary of its chat', () async {
    final db = FakeFirebaseFirestore();
    final user = db.collection('users').doc('u');
    await user.collection('memory').doc('f1').set({
      'text': 'Short walks help',
      'conversationId': 'c1',
    });
    await user.collection('memory').doc('f2').set({'text': 'Deadlines'});
    await user.collection('conversations').doc('c1').set({'summary': 'a'});
    await user.collection('conversations').doc('c2').set({'summary': 'b'});

    final fact = await user.collection('memory').doc('f1').get();
    await forgetFactBatch(db, fact).commit();

    final facts = await user.collection('memory').get();
    final chats = await user.collection('conversations').get();
    expect(facts.docs.map((d) => d.id), ['f2']);
    expect(chats.docs.map((d) => d.id), ['c2']);
  });
}
