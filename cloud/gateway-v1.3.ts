/**
 * SmartStir Lab gateway V1.3.0 (Bun/Railway Function).
 * Persistent Postgres users, labs, memberships, invitations, device claims,
 * per-device MQTT state, command acknowledgement and event logs.
 * Separate from the deployed V1.2.0 gateway until DATABASE_URL and MQTT ACL
 * are configured. Do not paste into the production function prematurely.
 */
import mqtt from "mqtt";
import postgres from "postgres";
import { createHash, randomBytes, randomUUID, scryptSync, timingSafeEqual } from "node:crypto";

const env = Bun.env;
if (!env.DATABASE_URL) throw Error("DATABASE_URL is required");
const db = postgres(env.DATABASE_URL, {
  max: 5, prepare: false,
  ssl: env.PGSSL === "require" ? "require" : undefined,
});
const q = (sql, params = []) => db.unsafe(sql, params);
const now = () => Math.floor(Date.now() / 1000);
const hash = value => createHash("sha256").update(value).digest("hex");
const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
  status, headers: { "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store", "x-content-type-options":"nosniff" },
});
const err = (message, code = 400) => json({detail:message}, code);
const validUser = value => /^[a-zA-Z0-9_]{3,24}$/.test(value);
const validDevice = value => /^[a-z0-9][a-z0-9-]{2,39}$/.test(value);
const failures = new Map();
const states = new Map();
const MQTT_PREFIX = "smartstir/v1/devices/";

async function initDb() {
  await q("CREATE TABLE IF NOT EXISTS users (id UUID PRIMARY KEY, username TEXT NOT NULL UNIQUE, password_salt TEXT NOT NULL, password_hash TEXT NOT NULL, created_at BIGINT NOT NULL)");
  await q("CREATE TABLE IF NOT EXISTS sessions (token_hash TEXT PRIMARY KEY, user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, expires_at BIGINT NOT NULL)");
  await q("CREATE TABLE IF NOT EXISTS labs (id UUID PRIMARY KEY, name TEXT NOT NULL, owner_id UUID NOT NULL REFERENCES users(id), created_at BIGINT NOT NULL)");
  await q("CREATE TABLE IF NOT EXISTS lab_members (lab_id UUID NOT NULL REFERENCES labs(id) ON DELETE CASCADE, user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, role TEXT NOT NULL CHECK(role IN ('owner','member')), PRIMARY KEY(lab_id,user_id))");
  await q("CREATE TABLE IF NOT EXISTS lab_invitations (id UUID PRIMARY KEY, lab_id UUID NOT NULL REFERENCES labs(id) ON DELETE CASCADE, user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, invited_by UUID NOT NULL REFERENCES users(id), status TEXT NOT NULL CHECK(status IN ('pending','accepted','declined')), created_at BIGINT NOT NULL, UNIQUE(lab_id,user_id))");
  await q("CREATE TABLE IF NOT EXISTS device_claims (device_id TEXT PRIMARY KEY, code_hash TEXT NOT NULL, last_seen BIGINT NOT NULL)");
  await q("CREATE TABLE IF NOT EXISTS devices (device_id TEXT PRIMARY KEY, lab_id UUID NOT NULL REFERENCES labs(id) ON DELETE CASCADE, label TEXT NOT NULL, claimed_by UUID NOT NULL REFERENCES users(id), created_at BIGINT NOT NULL)");
  await q("CREATE TABLE IF NOT EXISTS commands (command_id UUID PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID NOT NULL REFERENCES users(id), command TEXT NOT NULL, value INTEGER, status TEXT NOT NULL, ack_json TEXT, created_at BIGINT NOT NULL)");
  await q("CREATE TABLE IF NOT EXISTS device_events (id UUID PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), kind TEXT NOT NULL, data_json TEXT NOT NULL, created_at BIGINT NOT NULL)");
  await q("CREATE INDEX IF NOT EXISTS idx_commands_device_time ON commands(device_id,created_at DESC)");
  await q("CREATE INDEX IF NOT EXISTS idx_device_events_device_time ON device_events(device_id,created_at DESC)");
  // Legacy admin is migrated only from previously configured server-side scrypt
  // digest; no plaintext password is copied into the database.
  if (env.APP_USERNAME && env.APP_PASSWORD_HASH && env.APP_PASSWORD_SALT) {
    const uname = String(env.APP_USERNAME).toLowerCase();
    const id = randomUUID();
    await q("INSERT INTO users(id,username,password_salt,password_hash,created_at) VALUES($1,$2,$3,$4,$5) ON CONFLICT(username) DO NOTHING",
      [id,uname,env.APP_PASSWORD_SALT,env.APP_PASSWORD_HASH,now()]);
    const user = (await q("SELECT id FROM users WHERE username=$1",[uname]))[0];
    const existing = await q("SELECT id FROM labs WHERE owner_id=$1 LIMIT 1",[user.id]);
    if (!existing.length) {
      const labId = randomUUID();
      await q("INSERT INTO labs(id,name,owner_id,created_at) VALUES($1,$2,$3,$4)",[labId,"实验室 01",user.id,now()]);
      await q("INSERT INTO lab_members(lab_id,user_id,role) VALUES($1,$2,'owner')",[labId,user.id]);
      const deviceId = env.DEVICE_ID || "stirrer-001";
      if (validDevice(deviceId)) {
        await q("INSERT INTO devices(device_id,lab_id,label,claimed_by,created_at) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING",
          [deviceId,labId,"磁力搅拌器 01",user.id,now()]);
      }
    }
  }
}
await initDb();

function checkRate(id, limit, minutes) {
  const t=Date.now(), items=(failures.get(id)||[]).filter(x=>t-x<minutes*60000);
  if(items.length>=limit) return false;
  items.push(t);failures.set(id,items);return true;
}

async function body(req) {
  if (Number(req.headers.get("content-length")||"0") > 4096) throw Error("Body too large");
  const raw = await req.text();
  if (raw.length>4096) throw Error("Body too large");
  const data=JSON.parse(raw);
  if (!data || typeof data!=="object" || Array.isArray(data)) throw Error("Expected object");
  return data;
}

async function issueToken(userId) {
  const token=randomBytes(32).toString("base64url");
  await q("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,$3)",
    [hash(token),userId,now()+86400]);
  return json({access_token:token,expires_in:86400,token_type:"bearer"});
}

async function userFor(req) {
  const auth=req.headers.get("authorization")||"";
  if (!auth.startsWith("Bearer ")) return null;
  const token=auth.slice(7);
  if (token.length<16 || token.length>256) return null;
  const rows=await q("SELECT u.id,u.username FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>$2",
    [hash(token),now()]);
  return rows[0]||null;
}

async function roleFor(userId,labId) {
  if (!/^[0-9a-f-]{36}$/i.test(labId)) return null;
  const rows=await q("SELECT role FROM lab_members WHERE user_id=$1 AND lab_id=$2",[userId,labId]);
  return rows[0]?.role||null;
}

async function belongs(userId,deviceId) {
  if (!validDevice(deviceId)) return false;
  const rows=await q("SELECT 1 FROM devices d JOIN lab_members m ON m.lab_id=d.lab_id WHERE m.user_id=$1 AND d.device_id=$2",[userId,deviceId]);
  return rows.length>0;
}

function currentState(deviceId) {
  const s=states.get(deviceId);
  const alive=!!(mqttOnline && s && s.lastSeen && s.lastStateAt &&
    now()-s.lastSeen<=12 && now()-s.lastStateAt<=12);
  return {device_id:deviceId,online:alive,last_seen:s?.lastSeen??null,
    last_state_at:s?.lastStateAt??null,
    motor_enabled:alive?s.motor_enabled:null,pwm_percent:s?.pwm_percent??0,
    actual_rpm:alive?s.actual_rpm:null,armed:alive?!!s.armed:false,
    fault:s?.fault??null};
}

async function recordEvent(id,kind,obj) {
  if (!validDevice(id)) return;
  const found=await q("SELECT 1 FROM devices WHERE device_id=$1",[id]);
  if (!found.length)return;
  await q("INSERT INTO device_events(id,device_id,kind,data_json,created_at) VALUES($1,$2,$3,$4,$5)",
    [randomUUID(),id,kind,JSON.stringify(obj),now()]);
}

const client = env.MQTT_HOST && env.MQTT_USER && env.MQTT_PASSWORD
  ? mqtt.connect("mqtts://" + env.MQTT_HOST + ":" + (env.MQTT_PORT||"8883"),{
    clientId:"smartstir-gateway-v13-" + randomBytes(5).toString("hex"),
    username:env.MQTT_USER,password:env.MQTT_PASSWORD,
    protocolVersion:4,reconnectPeriod:5000,keepalive:25,clean:true,
    rejectUnauthorized:true,connectTimeout:10000})
  : null;
let mqttOnline=false;
if(client){
  client.on("connect",()=>{
    mqttOnline=true;
    client.subscribe(["state","presence","ack","event","pair"].map(
      suffix=>MQTT_PREFIX+"+/"+suffix),{qos:1},(e)=>{
      if(e)console.error("MQTT subscription failed",e.message);
    });
  });
  client.on("close",()=>mqttOnline=false);
  client.on("offline",()=>mqttOnline=false);
  client.on("error",e=>{mqttOnline=false;console.error("MQTT error",e.message);});
  client.on("message",(topic,data)=>{handleMqtt(topic,data).catch(
    e=>console.error("MQTT payload processing",e.message));});
}

async function handleMqtt(topic,payload) {
  const parts=topic.split("/");
  if(parts.length!==5 || parts[0]!=="smartstir" || parts[1]!=="v1" ||
      parts[2]!=="devices")return;
  const deviceId=parts[3], kind=parts[4];
  if (!validDevice(deviceId) || payload.length>2048) return;
  if(kind==="presence"){
    const s=states.get(deviceId)||{};
    s.lastSeen=now();
    if(payload.toString()==="offline"){s.lastStateAt=0;}
    states.set(deviceId,s);
    return;
  }
  let obj;try{obj=JSON.parse(payload.toString());}catch{return;}
  if(!obj||typeof obj!=="object"||Array.isArray(obj))return;
  if(kind==="pair"){
    const code=String(obj.pairing_code||"");
    if(code.length<16||code.length>64||! /^[A-Za-z0-9_-]+$/.test(code))return;
    await q("INSERT INTO device_claims(device_id,code_hash,last_seen) VALUES($1,$2,$3) ON CONFLICT(device_id) DO UPDATE SET code_hash=EXCLUDED.code_hash,last_seen=EXCLUDED.last_seen",
      [deviceId,hash(code),now()]);
    return;
  }
  if(kind==="state"){
    const s=states.get(deviceId)||{};
    for(const key of ["motor_enabled","pwm_percent","actual_rpm","armed","fault"])
      if(Object.prototype.hasOwnProperty.call(obj,key))s[key]=obj[key];
    s.lastSeen=now();s.lastStateAt=now();
    states.set(deviceId,s);return;
  }
  if(kind==="ack"){
    const commandId=String(obj.command_id||"");
    if(!/^[0-9a-f-]{36}$/i.test(commandId))return;
    if(!["APPLIED","REJECTED","FAILED","DUPLICATE"].includes(String(obj.status)))return;
    await q("UPDATE commands SET status=$1,ack_json=$2 WHERE command_id=$3 AND device_id=$4",
      [obj.status,JSON.stringify(obj),commandId,deviceId]);
    await recordEvent(deviceId,"command_ack",obj);return;
  }
  if(kind==="event")await recordEvent(deviceId,"device_event",obj);
}

Bun.serve({
  port:Number(env.PORT||"3000"),hostname:"0.0.0.0",
  async fetch(req) {
    const url=new URL(req.url),path=url.pathname,method=req.method.toUpperCase();
    try{
      if(path==="/health"&&method==="GET")
        return json({api:"ok",version:"1.3.0",mqtt_connected:mqttOnline,
          database:"configured",mode:"multi-tenant"});
      const ip=req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()||"unknown";
      if(path==="/api/v1/register"&&method==="POST"){
        if(!checkRate("reg:"+ip,6,30))return err("Too many registrations",429);
        const d=await body(req);
        const username=String(d.username||"").toLowerCase();
        const password=String(d.password||"");
        if(!validUser(username))return err("Username: 3-24 letters, digits or underscore",422);
        if(password.length<10||password.length>128||
          !/[a-z]/i.test(password)||!/[0-9]/.test(password))
          return err("Password needs at least 10 characters, letters and numbers",422);
        const salt=randomBytes(16).toString("hex");
        const digest=scryptSync(password,Buffer.from(salt,"hex"),32,
          {N:16384,r:8,p:1}).toString("hex");
        const existing=await q("SELECT 1 FROM users WHERE username=$1",[username]);
        if(existing.length)return err("Username is taken",409);
        const userId=randomUUID();
        await q("INSERT INTO users(id,username,password_salt,password_hash,created_at) VALUES($1,$2,$3,$4,$5)",
          [userId,username,salt,digest,now()]);
        const response=await issueToken(userId);
        return new Response(response.body,{status:201,headers:response.headers});
      }
      if(path==="/api/v1/login"&&method==="POST"){
        if(!checkRate("login:"+ip,12,5))return err("Too many login attempts",429);
        const d=await body(req),username=String(d.username||"").toLowerCase();
        const password=String(d.password||"");
        const rows=await q("SELECT id,password_salt,password_hash FROM users WHERE username=$1",[username]);
        if(!rows.length || password.length>128)return err("Invalid credentials",401);
        const user=rows[0];
        const digest=scryptSync(password,Buffer.from(user.password_salt,"hex"),32,
          {N:16384,r:8,p:1});
        const expected=Buffer.from(user.password_hash,"hex");
        if(expected.length!==digest.length||!timingSafeEqual(expected,digest))
          return err("Invalid credentials",401);
        return issueToken(user.id);
      }
      const user=await userFor(req);
      if(!user)return err("Login required",401);
      if(path==="/api/v1/logout"&&method==="POST"){
        await q("DELETE FROM sessions WHERE token_hash=$1",
          [hash((req.headers.get("authorization")||"").slice(7))]);
        return json({ok:true});
      }
      if(path==="/api/v1/me"&&method==="GET")return json(user);
      if(path==="/api/v1/labs"&&method==="GET"){
        return json(await q("SELECT l.id,l.name,m.role FROM labs l JOIN lab_members m ON m.lab_id=l.id WHERE m.user_id=$1 ORDER BY l.created_at DESC",[user.id]));
      }
      if(path==="/api/v1/labs"&&method==="POST"){
        const d=await body(req),name=String(d.name||"").trim();
        if(name.length<2||name.length>64)return err("Lab name must have 2-64 characters",422);
        const labId=randomUUID();
        await db.begin(async tx=>{
          await tx.unsafe("INSERT INTO labs(id,name,owner_id,created_at) VALUES($1,$2,$3,$4)",
            [labId,name,user.id,now()]);
          await tx.unsafe("INSERT INTO lab_members(lab_id,user_id,role) VALUES($1,$2,'owner')",
            [labId,user.id]);
        });
        return json({id:labId,name,role:"owner"},201);
      }
      if(path==="/api/v1/invitations"&&method==="GET"){
        return json(await q("SELECT i.id,l.name AS lab_name,u.username AS invited_by FROM lab_invitations i JOIN labs l ON l.id=i.lab_id JOIN users u ON u.id=i.invited_by WHERE i.user_id=$1 AND i.status='pending' ORDER BY i.created_at DESC",
          [user.id]));
      }
      const inv=path.match(/^\/api\/v1\/invitations\/([0-9a-f-]{36})\/(accept|decline)$/i);
      if(inv&&method==="POST"){
        const rows=await q("SELECT id,lab_id FROM lab_invitations WHERE id=$1 AND user_id=$2 AND status='pending'",
          [inv[1],user.id]);
        if(!rows.length)return err("Invitation not found",404);
        await db.begin(async tx=>{
          if(inv[2]==="accept")
            await tx.unsafe("INSERT INTO lab_members(lab_id,user_id,role) VALUES($1,$2,'member') ON CONFLICT DO NOTHING",
              [rows[0].lab_id,user.id]);
          await tx.unsafe("UPDATE lab_invitations SET status=$1 WHERE id=$2 AND status='pending'",
            [inv[2]==="accept"?"accepted":"declined",inv[1]]);
        });
        return json({ok:true});
      }
      const labPath=path.match(/^\/api\/v1\/labs\/([0-9a-f-]{36})\/(devices|invitations|members)$/i);
      if(labPath){
        const labId=labPath[1],kind=labPath[2];
        const role=await roleFor(user.id,labId);
        if(!role)return err("Laboratory not found",404);
        if(kind==="devices"&&method==="GET"){
          const rows=await q("SELECT device_id,label FROM devices WHERE lab_id=$1 ORDER BY created_at DESC",[labId]);
          return json(rows.map(row=>({...row,online:currentState(row.device_id).online})));
        }
        if(kind==="members"&&method==="GET")
          return json(await q("SELECT u.username,m.role FROM lab_members m JOIN users u ON u.id=m.user_id WHERE m.lab_id=$1 ORDER BY m.role DESC,u.username",[labId]));
        if(role!=="owner")return err("Owner access required",403);
        if(kind==="invitations"&&method==="POST"){
          const d=await body(req),username=String(d.username||"").toLowerCase();
          const rows=await q("SELECT id FROM users WHERE username=$1",[username]);
          if(!rows.length)return err("Registered user not found",404);
          if(rows[0].id===user.id)return err("Cannot invite yourself",422);
          const current=await roleFor(rows[0].id,labId);
          if(current)return err("Already a member",409);
          const id=randomUUID();
          await q("INSERT INTO lab_invitations(id,lab_id,user_id,invited_by,status,created_at) VALUES($1,$2,$3,$4,'pending',$5) ON CONFLICT(lab_id,user_id) DO UPDATE SET status='pending',invited_by=EXCLUDED.invited_by,created_at=EXCLUDED.created_at",
            [id,labId,rows[0].id,user.id,now()]);
          return json({ok:true},201);
        }
        if(kind==="devices"&&method==="POST"){
          const d=await body(req),deviceId=String(d.device_id||"").trim();
          const code=String(d.pairing_code||""),label=String(d.label||deviceId).trim();
          if(!validDevice(deviceId)||code.length<16||code.length>64||
              label.length<1||label.length>64)return err("Invalid device ID, pairing code or name",422);
          const claimed=await q("SELECT lab_id FROM devices WHERE device_id=$1",[deviceId]);
          if(claimed.length)return err("This ESP32 belongs to a laboratory",409);
          const pair=await q("SELECT code_hash,last_seen FROM device_claims WHERE device_id=$1",[deviceId]);
          if(!pair.length||now()-Number(pair[0].last_seen)>300||
              pair[0].code_hash!==hash(code))
            return err("ESP32 pairing proof not found; connect firmware to MQTT and retry",409);
          const result=await q("INSERT INTO devices(device_id,lab_id,label,claimed_by,created_at) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING RETURNING device_id",
            [deviceId,labId,label,user.id,now()]);
          if(!result.length)return err("Device was claimed already",409);
          return json({device_id:deviceId,label},201);
        }
      }
      if(path==="/api/v1/devices"&&method==="GET"){
        const rows=await q("SELECT d.device_id,d.label FROM devices d JOIN lab_members m ON m.lab_id=d.lab_id WHERE m.user_id=$1",[user.id]);
        return json(rows.map(row=>({...row,...currentState(row.device_id)})));
      }
      const devicePath=path.match(/^\/api\/v1\/devices\/([a-z0-9-]+)(?:\/(events|commands)(?:\/([0-9a-f-]{36}))?)?$/i);
      if(devicePath){
        const deviceId=devicePath[1],kind=devicePath[2],commandId=devicePath[3];
        if(!await belongs(user.id,deviceId))return err("Device not found",404);
        if(!kind&&method==="GET")return json(currentState(deviceId));
        if(kind==="events"&&method==="GET")
          return json(await q("SELECT kind,data_json,created_at FROM device_events WHERE device_id=$1 ORDER BY created_at DESC LIMIT 100",[deviceId]));
        if(kind==="commands"&&commandId&&method==="GET"){
          const rows=await q("SELECT command_id,command,value,status,ack_json,created_at FROM commands WHERE device_id=$1 AND command_id=$2",[deviceId,commandId]);
          if(!rows.length)return err("Command not found",404);
          if(rows[0].status==="PENDING"&&now()-Number(rows[0].created_at)>10)
            rows[0].status="TIMEOUT";
          return json(rows[0]);
        }
        if(kind==="commands"&&!commandId&&method==="POST"){
          const d=await body(req),command=String(d.command||"");
          if(!["START","STOP","SET_PWM"].includes(command))return err("Invalid command",422);
          if(command==="SET_PWM" && (!Number.isInteger(d.value)||d.value<0||d.value>100))
            return err("PWM must be an integer 0..100",422);
          if(command!=="SET_PWM"&&d.value!=null)return err("Unexpected value",422);
          if(!mqttOnline||!client)return err("MQTT service offline",503);
          if(command!=="STOP"&&!currentState(deviceId).online)return err("Device offline",409);
          const id=randomUUID(),time=now();
          await q("INSERT INTO commands(command_id,device_id,user_id,command,value,status,created_at) VALUES($1,$2,$3,$4,$5,'PENDING',$6)",
            [id,deviceId,user.id,command,command==="SET_PWM"?d.value:null,time]);
          const packet={version:1,command_id:id,command,issued_at:time,expires_at:time+5};
          if(command==="SET_PWM")packet.value=d.value;
          try {
            await new Promise((resolve,reject)=>client.publish(
              MQTT_PREFIX+deviceId+"/cmd",JSON.stringify(packet),
              {qos:1,retain:false},e=>e?reject(e):resolve()));
          }catch(e){
            await q("UPDATE commands SET status='FAILED' WHERE command_id=$1",[id]);
            return err("Unable to publish command",503);
          }
          await recordEvent(deviceId,"command_sent",{command_id:id,command,user:user.username});
          return json({command_id:id,status:"PENDING"},202);
        }
      }
      return err("Not found",404);
    }catch(e){
      console.error("Request failed",e.message);
      if(e.code==="23505")return err("Already exists",409);
      if(e.message?.includes("Body too large"))return err("Body too large",413);
      if(e instanceof SyntaxError)return err("Invalid JSON",400);
      return err("Server error",500);
    }
  },
});
