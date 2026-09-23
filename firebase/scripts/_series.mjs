import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
const app = initializeApp({ credential: applicationDefault(), projectId: 'gym-sas' });
const db = getFirestore(app);
const t = db.doc('tenants/nxt_performance_studio');
const staff = new Map();
for (const d of (await t.collection('staff').get()).docs) staff.set(d.id, d.get('name'));
console.log('SÉRIES');
for (const d of (await t.collection('sessionSeries').get()).docs) {
  console.log(`  ${d.id}`);
  console.log(`    instrutor=${d.get('instructorId') ?? 'NENHUM'} (${staff.get(d.get('instructorId')) ?? '—'})`);
  console.log(`    dia=${d.get('dayOfWeek')} ${d.get('startTime')} +${d.get('durationMinutes')}min  status=${d.get('status')}`);
}
process.exit(0);
