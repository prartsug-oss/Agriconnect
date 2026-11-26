import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to view orders." }, { status: 401 });

    const { data, error } = await supabase
      .from("orders")
      .select("id,buyer_id,seller_id,quantity,unit_price,total_amount,status,delivery_district,notes,created_at,produce_listings(title,unit,district)")
      .or(`buyer_id.eq.${user.id},seller_id.eq.${user.id}`)
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    return NextResponse.json({ orders: data ?? [] });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to load orders.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to place an order." }, { status: 401 });

    const body = await request.json();
    const listingId = typeof body.listing_id === "string" ? body.listing_id : "";
    const quantity = Number(body.quantity);
    const deliveryDistrict = typeof body.delivery_district === "string" ? body.delivery_district.trim() : "";
    if (!listingId || !Number.isFinite(quantity) || quantity <= 0 || !deliveryDistrict || deliveryDistrict.length > 80) {
      return NextResponse.json({ error: "Provide a valid listing, quantity and delivery district." }, { status: 400 });
    }

    const { data, error } = await supabase.rpc("create_order_request", {
      p_listing_id: listingId,
      p_quantity: quantity,
      p_delivery_district: deliveryDistrict,
      p_notes: typeof body.notes === "string" ? body.notes.slice(0, 500) : null,
    });
    if (error) throw error;
    return NextResponse.json({ order: data }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to place order.";
    const status = message.includes("Sign in") ? 401 : message.includes("not available") || message.includes("stock") ? 409 : message.includes("not configured") ? 503 : 400;
    return NextResponse.json({ error: message, }, { status });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to update orders." }, { status: 401 });

    const body = await request.json();
    const orderId = typeof body.order_id === "string" ? body.order_id : "";
    const status = typeof body.status === "string" ? body.status : "";
    if (!orderId || !["accepted", "in_transit", "completed", "cancelled"].includes(status)) {
      return NextResponse.json({ error: "Provide a valid order and status." }, { status: 400 });
    }

    const { data, error } = await supabase.rpc("update_order_status", {
      p_order_id: orderId,
      p_status: status,
    });
    if (error) throw error;
    return NextResponse.json({ order: data });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to update order.";
    const status = message.includes("Sign in") ? 401 : message.includes("not found") ? 404 : message.includes("not configured") ? 503 : 400;
    return NextResponse.json({ error: message }, { status });
  }
}
