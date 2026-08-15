// Sign in as a demo user with @supabase/ssr and print the cookie header value the app expects.
import { createServerClient } from "@supabase/ssr";
import fs from "node:fs";
const env = Object.fromEntries(fs.readFileSync(".env.local","utf8").split(/\r?\n/).filter(l=>l && !l.startsWith('#') && l.includes('=')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i).trim(), l.slice(i+1).trim()];}));
const [email, password] = process.argv.slice(2);
const jar = new Map();
const s = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { cookies: { getAll(){ return [...jar].map(([name,value])=>({name,value})); }, setAll(cs){ cs.forEach(c=>jar.set(c.name,c.value)); } } });
const { error } = await s.auth.signInWithPassword({ email, password });
if (error) { console.error("LOGIN FAILED", error.message); process.exit(1); }
process.stdout.write([...jar].map(([n,v])=>`${n}=${v}`).join("; "));
