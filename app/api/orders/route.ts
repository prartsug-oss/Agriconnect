import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to view orders." }, { status: 401 });

    const { data, error } = await supabase
      .from("orders")
      .select("id,quantity,unit_price,total_amount,status,delivery_district,notes,created_at,produce_listings(title,unit,district)")
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

    const { data: listing, error: listingError } = await supabase
      .from("produce_listings")
      .select("id,seller_id,quantity,price_per_unit,status")
      .eq("id", listingId)
      .eq("status", "active")
      .single();

    if (listingError || !listing) return NextResponse.json({ error: "This listing is no longer available." }, { status: 404 });
    if (listing.seller_id === user.id) return NextResponse.json({ error: "You cannot order your own listing." }, { status: 400 });
    if (quantity > Number(listing.quantity)) return NextResponse.json({ error: "Requested quantity exceeds the available stock." }, { status: 400 });

    const { data, error } = await supabase.from("orders").insert({
      listing_id: listing.id,
      buyer_id: user.id,
      seller_id: listing.seller_id,
      quantity,
      unit_price: listing.price_per_unit,
      delivery_district: deliveryDistrict,
      notes: typeof body.notes === "string" ? body.notes.slice(0, 500) : null,
    }).select("id,quantity,unit_price,total_amount,status,delivery_district,created_at").single();

    if (error) throw error;
    return NextResponse.json({ order: data }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to place order.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
