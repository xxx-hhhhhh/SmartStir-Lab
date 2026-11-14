/**
 * Integration fixture for CSV API only. Run against disposable TEST database.
 */
import postgres from "postgres";
import {randomUUID} from "node:crypto";
const labId=process.argv[2];
if(!Bun.env.DATABASE_URL || !labId)throw Error("Missing test database or lab ID");
const db=postgres(Bun.env.DATABASE_URL,{prepare:false});
const owner=(await db.unsafe("SELECT user_id FROM lab_members WHERE lab_id=$1 AND role='owner'",[labId]))[0];
if(!owner)throw Error("Test lab owner missing");
const deviceId="stirrer-csvtest";
await db.unsafe("INSERT INTO devices(device_id,lab_id,label,claimed_by,created_at) VALUES($1,$2,'CSV Test ESP32',$3,$4)",[deviceId,labId,owner.user_id,Math.floor(Date.now()/1000)]);
const id=randomUUID();
await db.unsafe("INSERT INTO experiment_runs(id,device_id,started_at,ended_at,end_reason,sample_count) VALUES($1,$2,now()-interval '6 seconds',now(),'stopped',2)",[id,deviceId]);
await db.unsafe("INSERT INTO experiment_samples(run_id,motor_enabled,pwm_percent,actual_rpm,fault,uptime_ms) VALUES($1,true,30,NULL,NULL,3000),($1,false,0,NULL,$2,6000)",[id,'=HYPERLINK("https://example.com","x")']);
console.log(id);
await db.end();
