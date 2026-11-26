import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to view notifications." }, { status: 401 });
    const { data, error } = await supabase.from("notifications")
      .select("id,type,title,message,related_id,is_read,created_at")
      .order("created_at", { ascending: false }).limit(50);
    if (error) throw error;
    return NextResponse.json({ notifications: data ?? [], unread_count: (data ?? []).filter(item => !item.is_read).length });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to load notifications.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to update notifications." }, { status: 401 });
    const body = await request.json().catch(() => ({}));
    const notificationId = typeof body.notification_id === "string" ? body.notification_id : null;
    const { data, error } = await supabase.rpc("mark_notification_read", { p_notification_id: notificationId });
    if (error) throw error;
    return NextResponse.json({ updated: data ?? 0 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to update notifications.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 400 });
  }
}
