import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  try {
    const supabase = await createClient();
    const { data: { user }, error } = await supabase.auth.getUser();
    if (error || !user) return NextResponse.json({ user: null });
    const { data: profile } = await supabase.from("profiles").select("full_name,role,district,business_name").eq("id", user.id).maybeSingle();
    return NextResponse.json({ user: { id: user.id, email: user.email, ...profile } });
  } catch {
    return NextResponse.json({ user: null, configured: false });
  }
}

export async function DELETE() {
  try {
    const supabase = await createClient();
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    return NextResponse.json({ success: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to sign out.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
