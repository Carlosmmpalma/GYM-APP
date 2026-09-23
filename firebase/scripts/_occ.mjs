import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
const app = initializeApp({ credential: applicationDefault(), projectId: 'gym-sas' });
const db = getFirestore(app);
const t = db.doc('tenants/nxt_performance_studio');
const s = await t.collection('sessionOccurrences').where('startAt','>=',new Date()).orderBy('startAt').limit(12).get();
for (const d of s.docs) {
  const a = d.get('startAt').toDate(), b = d.get('endAt')?.toDate();
  console.log(`  ${a.toISOString().slice(0,16)} → ${b ? b.toISOString().slice(0,16) : 'SEM endAt'}  instrutor=${(d.get('instructorId')??'—').slice(0,8)}  status=${d.get('status')}`);
}
console.log(`\n(${s.size} mostradas)`);
process.exit(0);
