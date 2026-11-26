import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to view deliveries." }, { status: 401 });

    const { data, error } = await supabase
      .from("delivery_requests")
      .select("id,order_id,buyer_id,seller_id,transporter_id,pickup_district,delivery_district,delivery_fee,status,created_at,delivery_quotes(id,transporter_id,fee,notes,status,created_at)")
      .or(`buyer_id.eq.${user.id},seller_id.eq.${user.id},transporter_id.eq.${user.id}`)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    return NextResponse.json({ deliveries: data ?? [] });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to load deliveries.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to manage deliveries." }, { status: 401 });
    const body = await request.json();
    const action = typeof body.action === "string" ? body.action : "";
    let rpc: string;
    let args: Record<string, unknown>;
    if (action === "request") {
      if (typeof body.order_id !== "string") return NextResponse.json({ error: "Choose a valid order." }, { status: 400 });
      rpc = "create_delivery_request";
      args = { p_order_id: body.order_id, p_pickup_district: typeof body.pickup_district === "string" ? body.pickup_district : null };
    } else if (action === "quote") {
      const fee = Number(body.fee);
      if (typeof body.delivery_id !== "string" || !Number.isFinite(fee) || fee < 0) return NextResponse.json({ error: "Provide a delivery and a valid fee." }, { status: 400 });
      rpc = "submit_delivery_quote";
      args = { p_delivery_id: body.delivery_id, p_fee: fee, p_notes: typeof body.notes === "string" ? body.notes.slice(0, 300) : null };
    } else if (action === "choose") {
      if (typeof body.quote_id !== "string") return NextResponse.json({ error: "Choose a valid quote." }, { status: 400 });
      rpc = "choose_delivery_quote";
      args = { p_quote_id: body.quote_id };
    } else if (action === "status") {
      if (typeof body.delivery_id !== "string" || !["picked_up", "delivered", "cancelled"].includes(body.status)) return NextResponse.json({ error: "Provide a valid delivery status." }, { status: 400 });
      rpc = "update_delivery_status";
      args = { p_delivery_id: body.delivery_id, p_status: body.status };
    } else {
      return NextResponse.json({ error: "Unknown delivery action." }, { status: 400 });
    }
    const { data, error } = await supabase.rpc(rpc, args);
    if (error) throw error;
    return NextResponse.json({ result: data }, { status: action === "request" ? 201 : 200 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to process delivery action.";
    const status = message.includes("Sign in") ? 401 : message.includes("not found") ? 404 : message.includes("not configured") ? 503 : 400;
    return NextResponse.json({ error: message }, { status });
  }
}
