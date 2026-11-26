"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { Sprout, ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

export default function AuthForm(){
 const [mode,setMode]=useState<"signin"|"signup">("signin");
 const [busy,setBusy]=useState(false);
 const [message,setMessage]=useState("");
 async function submit(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setMessage("");
  const data=new FormData(e.currentTarget);const email=String(data.get("email"));const password=String(data.get("password"));
  try{
   const supabase=createClient();
   if(mode==="signup"){
    const {error}=await supabase.auth.signUp({email,password,options:{emailRedirectTo:`${window.location.origin}/auth/callback`,data:{full_name:String(data.get("name")||""),role:String(data.get("role")||"farmer")}}});
    if(error)throw error;setMessage("Account request submitted. Check your email if confirmation is enabled.");
   }else{
    const {error}=await supabase.auth.signInWithPassword({email,password});if(error)throw error;window.location.href="/";
   }
  }catch(err){setMessage(err instanceof Error?err.message:"Something went wrong.");}
  finally{setBusy(false);}
 }
 return <main style={{minHeight:"100vh",display:"grid",gridTemplateColumns:"minmax(0,1fr) minmax(340px, .85fr)",background:"#f7f9f6"}}>
  <section style={{background:"#123d2b",color:"#fff",padding:"48px 8vw",display:"flex",flexDirection:"column",justifyContent:"space-between"}}>
   <div style={{display:"flex",alignItems:"center",gap:11}}><div className="brand-mark"><Sprout size={23}/></div><div><div className="brand-name">AgriConnect</div><div className="brand-sub">Grow together</div></div></div>
   <div style={{maxWidth:490}}><div className="eyebrow" style={{color:"#c1d5c5"}}>OPPORTUNITY STARTS HERE</div><h1 style={{fontSize:"clamp(36px,5vw,60px)",letterSpacing:"-2.8px",lineHeight:1.03,margin:"18px 0"}}>Good things grow when we connect.</h1><p style={{color:"#c3d6c9",lineHeight:1.8,fontSize:14}}>A smarter way to trade, discover and grow across Uganda’s agricultural economy.</p></div>
   <div style={{fontSize:11,color:"#a9c4b4"}}>Built for the people who feed our future.</div>
  </section>
  <section style={{display:"grid",placeItems:"center",padding:28}}><div style={{width:"min(390px,100%)"}}><Link href="/" style={{display:"inline-flex",alignItems:"center",gap:7,color:"#68766c",textDecoration:"none",fontSize:12,marginBottom:35}}><ArrowLeft size={14}/> Back to AgriConnect</Link><div className="eyebrow">YOUR AGRICULTURAL NETWORK</div><h2 style={{fontSize:29,letterSpacing:-1,margin:"9px 0"}}>{mode==="signin"?"Welcome back":"Create your account"}</h2><p className="subtext">{mode==="signin"?"Sign in to continue to your workspace.":"Join a growing network of farmers and businesses."}</p>
  <form onSubmit={submit}>{mode==="signup"&&<><div className="form-field"><label>Full name</label><input name="name" required placeholder="Your full name"/></div><div className="form-field"><label>I am joining as</label><select name="role"><option value="farmer">Farmer</option><option value="buyer">Buyer</option><option value="supplier">Supplier</option><option value="logistics">Logistics provider</option></select></div></>}<div className="form-field"><label>Email address</label><input name="email" type="email" required placeholder="you@example.com"/></div><div className="form-field"><label>Password</label><input name="password" type="password" minLength={6} required placeholder="At least 6 characters"/></div><button className="primary-btn" disabled={busy} style={{width:"100%",justifyContent:"center",marginTop:20,padding:13}}>{busy?"Please wait…":mode==="signin"?"Sign in":"Create account"}</button></form>
  {message&&<p style={{fontSize:12,color:message.includes("submitted")?"#31704a":"#a34d3c",lineHeight:1.5,marginTop:13}}>{message}</p>}
  <p style={{fontSize:12,color:"#78847d",marginTop:22,textAlign:"center"}}>{mode==="signin"?"New to AgriConnect?":"Already have an account?"} <button onClick={()=>{setMode(mode==="signin"?"signup":"signin");setMessage("")}} style={{color:"#246746",fontWeight:700}}>{mode==="signin"?"Create an account":"Sign in"}</button></p>
  <p style={{fontSize:10,color:"#a0aaa2",lineHeight:1.5,marginTop:24}}>Authentication requires your own Supabase project credentials. The dashboard preview does not create or store a real account.</p></div></section>
 </main>;
}
