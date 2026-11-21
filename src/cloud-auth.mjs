// Dependency-free OAuth PKCE adapter for Supabase Cloud. No secret or service-role key is used in-browser.
const conf = () => globalThis.HATOP_CONFIG || {};
const cleanBase = () => String(conf().url || '').replace(/\/+$/, '');
const key = () => String(conf().publishableKey || '');
const STORAGE_SESSION = 'hatop_cloud_session_v1';
const STORAGE_VERIFIER = 'hatop_cloud_pkce_v1';
const toBase64Url = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/g,'');
const makeVerifier = () => toBase64Url(crypto.getRandomValues(new Uint8Array(48)));
async function makeChallenge(v){return toBase64Url(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v))));}
export function getSession(){try {return JSON.parse(localStorage.getItem(STORAGE_SESSION)||'null');} catch{return null;}}
function setSession(value){ if(value) localStorage.setItem(STORAGE_SESSION,JSON.stringify(value)); else localStorage.removeItem(STORAGE_SESSION); }
export async function logout(){
 const session=getSession();
 try {if(session?.access_token) await fetch(`${cleanBase()}/auth/v1/logout`,{method:'POST',headers:{apikey:key(),Authorization:`Bearer ${session.access_token}`}});}
 catch { /* Local logout must succeed even if provider is temporarily unreachable. */ }
 finally {setSession(null);}
}
export async function startGoogleLogin(){
 const verifier=makeVerifier(); sessionStorage.setItem(STORAGE_VERIFIER,verifier);
 const challenge=await makeChallenge(verifier);
 const redirect=location.origin+location.pathname;
 const target=new URL(`${cleanBase()}/auth/v1/authorize`);
 target.searchParams.set('provider','google'); target.searchParams.set('redirect_to',redirect);
 target.searchParams.set('code_challenge',challenge); target.searchParams.set('code_challenge_method','s256');
 location.assign(target.toString());
}
export async function handleGoogleReturn(){
 const params=new URLSearchParams(location.search);
 if(params.has('error')) throw new Error(params.get('error_description') || params.get('error'));
 const code=params.get('code'); if(!code) return false;
 const verifier=sessionStorage.getItem(STORAGE_VERIFIER);
 if(!verifier) throw new Error('Sesi login tidak tersedia. Ulangi login Google pada tab yang sama.');
 const res=await fetch(`${cleanBase()}/auth/v1/token?grant_type=pkce`,{
  method:'POST',headers:{apikey:key(),'Content-Type':'application/json'},
  body:JSON.stringify({auth_code:code,code_verifier:verifier})
 });
 const body=await res.json();if(!res.ok) throw new Error(body.msg||body.error_description||'Gagal menukar kode login');
 setSession({...body,expires_at:Math.floor(Date.now()/1000)+body.expires_in});
 sessionStorage.removeItem(STORAGE_VERIFIER);
 history.replaceState(null,'',location.pathname+'#/');
 return true;
}
export async function accessToken(){
 const session=getSession();if(!session?.access_token) return null;
 if((session.expires_at||0)>Math.floor(Date.now()/1000)+60) return session.access_token;
 const res=await fetch(`${cleanBase()}/auth/v1/token?grant_type=refresh_token`,{
  method:'POST',headers:{apikey:key(),'Content-Type':'application/json'},body:JSON.stringify({refresh_token:session.refresh_token})
 });
 const body=await res.json();
 if(!res.ok || !body.access_token){setSession(null);throw new Error('Sesi berakhir. Masuk kembali dengan Google.');}
 setSession({...body,expires_at:Math.floor(Date.now()/1000)+body.expires_in});
 return body.access_token;
}
export async function apiFetch(path,{method='GET',body=null,requireAuth=true}={}){
 const token=requireAuth?await accessToken():null;
 if(requireAuth && !token) throw new Error('Silakan login Google terlebih dahulu.');
 const url=`${cleanBase()}${path}`;
 const headers={apikey:key(),'Content-Type':'application/json',Prefer:'return=representation'};
 if(token) headers.Authorization=`Bearer ${token}`;
 const res=await fetch(url,{method,headers,body:body===null?undefined:JSON.stringify(body)});
 let data=null;try{data=await res.json();}catch{}
 if(!res.ok) throw new Error(data?.message||data?.msg||data?.error_description||`HTTP ${res.status}`);
 return data;
}
export async function loadTable(table,query='select=*',requireAuth=true){return await apiFetch(`/rest/v1/${table}?${query}`,{requireAuth});}
export async function action(name,payload={}){return await apiFetch('/rest/v1/rpc/hatop_action',{method:'POST',body:{p_action:name,p_data:payload}});}
export async function getIdentity(){return (await apiFetch('/auth/v1/user')).id;}
export function configured(){return /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(cleanBase()) && key().startsWith('sb_publishable_');}
