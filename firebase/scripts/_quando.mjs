import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
const app = initializeApp({ credential: applicationDefault(), projectId: 'gym-sas' });
const db = getFirestore(app);
const t = db.doc('tenants/nxt_performance_studio');
const docs = (await t.collection('sessionSeries').get()).docs
  .map(d => ({ id: d.id, dia: d.get('dayOfWeek'), hora: d.get('startTime'),
               dur: d.get('durationMinutes'),
               criada: d.get('createdAt')?.toDate?.()?.toISOString() ?? '?' }))
  .sort((a,b) => a.criada.localeCompare(b.criada));
for (const d of docs) console.log(`  ${d.criada}  dia=${d.dia} ${d.hora} +${d.dur}`);
process.exit(0);
