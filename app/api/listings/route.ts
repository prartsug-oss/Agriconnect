import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  try {
    const supabase = await createClient();
    const query = request.nextUrl.searchParams.get("q")?.trim();
    const category = request.nextUrl.searchParams.get("category");
    let builder = supabase
      .from("produce_listings")
      .select("id,title,category,description,quantity,unit,price_per_unit,district,status,created_at,profiles(full_name,business_name)")
      .eq("status", "active")
      .order("created_at", { ascending: false })
      .limit(100);

    if (request.nextUrl.searchParams.get("mine") === "true") {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return NextResponse.json({ error: "Sign in to view your listings." }, { status: 401 });
      builder = builder.eq("seller_id", user.id);
    }

    if (query) builder = builder.or(`title.ilike.%${query.replace(/[,%()]/g, "")}%,district.ilike.%${query.replace(/[,%()]/g, "")}%`);
    if (category && category !== "All produce") builder = builder.eq("category", category);

    const { data, error } = await builder;
    if (error) throw error;
    return NextResponse.json({ listings: data ?? [] });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to load listings.";
    const status = message.includes("not configured") ? 503 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to publish a listing." }, { status: 401 });

    const { data: profile, error: profileError } = await supabase.from("profiles").select("role").eq("id", user.id).single();
    if (profileError || !profile || !["farmer", "supplier"].includes(profile.role)) {
      return NextResponse.json({ error: "Only farmer and supplier accounts can publish produce listings." }, { status: 403 });
    }

    const body = await request.json();
    const title = typeof body.title === "string" ? body.title.trim() : "";
    const category = typeof body.category === "string" ? body.category.trim() : "";
    const district = typeof body.district === "string" ? body.district.trim() : "";
    const unit = typeof body.unit === "string" ? body.unit.trim() : "kg";
    const quantity = Number(body.quantity);
    const price = Number(body.price_per_unit);

    if (!title || title.length > 120 || !category || category.length > 50 || !district || district.length > 80) {
      return NextResponse.json({ error: "Enter a valid produce name, category and district." }, { status: 400 });
    }
    if (!Number.isFinite(quantity) || quantity <= 0 || !Number.isFinite(price) || price < 0) {
      return NextResponse.json({ error: "Quantity must be above zero and price cannot be negative." }, { status: 400 });
    }

    const { data, error } = await supabase.from("produce_listings").insert({
      seller_id: user.id,
      title,
      category,
      district,
      unit,
      quantity,
      price_per_unit: price,
      description: typeof body.description === "string" ? body.description.slice(0, 1000) : null,
    }).select("id,title,category,description,quantity,unit,price_per_unit,district,status,created_at").single();

    if (error) throw error;
    return NextResponse.json({ listing: data }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to create listing.";
    const status = message.includes("not configured") ? 503 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
