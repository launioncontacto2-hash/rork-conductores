import { execFileSync } from 'node:child_process';
const host=process.env.SUPABASE_DB_HOST||'127.0.0.1'; if(!['127.0.0.1','localhost'].includes(host)) throw new Error('non-local database host');
const container=process.env.SUPABASE_DB_CONTAINER||'supabase_db_rork-conductores';
export function localQuery(sql){ const out=execFileSync('docker',['exec','-i',container,'psql','-U','postgres','-d','postgres','-X','-A','-t','-F','|','-c',sql],{encoding:'utf8'}).trim(); return out?out.split(/\r?\n/).map(x=>x.split('|')):[]; }
export function localSimulationCase(id){ return localQuery(`SELECT id,status,expires_at,driver_profile_id,environment_id,station_id FROM public.dori_copilot_simulation_cases WHERE id='${id}'`); }
export function localEvaluationCount(id){ return localQuery(`SELECT count(*) FROM public.dori_copilot_simulation_evaluations WHERE case_id='${id}'`)[0]?.[0]||'0'; }
