import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to browse business partners." }, { status: 401 });

    const role = request.nextUrl.searchParams.get("role");
    if (role !== "supplier" && role !== "logistics") {
      return NextResponse.json({ error: "Choose supplier or logistics partners." }, { status: 400 });
    }
    const q = (request.nextUrl.searchParams.get("q") || "").trim().slice(0, 80);
    let query = supabase.from("profiles")
      .select("id,full_name,business_name,role,phone,district,service_description,coverage_districts,is_verified")
      .eq("role", role)
      .order("business_name", { ascending: true })
      .limit(100);
    if (q) query = query.or(`business_name.ilike.%${q.replace(/[,%()]/g, "")}%,full_name.ilike.%${q.replace(/[,%()]/g, "")}%,district.ilike.%${q.replace(/[,%()]/g, "")}%`);
    const { data, error } = await query;
    if (error) throw error;
    return NextResponse.json({ partners: data ?? [] });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to load business partners.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to update your business profile." }, { status: 401 });

    const { data: profile, error: profileError } = await supabase.from("profiles").select("role").eq("id", user.id).single();
    if (profileError || !profile || !["supplier", "logistics"].includes(profile.role)) {
      return NextResponse.json({ error: "Only supplier and logistics accounts can publish a partner profile." }, { status: 403 });
    }

    const body = await request.json();
    const businessName = typeof body.business_name === "string" ? body.business_name.trim() : "";
    const phone = typeof body.phone === "string" ? body.phone.trim() : "";
    const district = typeof body.district === "string" ? body.district.trim() : "";
    const description = typeof body.service_description === "string" ? body.service_description.trim() : "";
    const coverage = typeof body.coverage_districts === "string" ? body.coverage_districts.trim() : "";

    if (!businessName || businessName.length > 120 || !district || district.length > 80 || description.length > 600 || coverage.length > 250 || phone.length > 30) {
      return NextResponse.json({ error: "Add a business name, district and valid contact details." }, { status: 400 });
    }

    const { data, error } = await supabase.from("profiles").update({
      business_name: businessName,
      phone: phone || null,
      district,
      service_description: description || null,
      coverage_districts: coverage || null,
      updated_at: new Date().toISOString(),
    }).eq("id", user.id)
      .select("id,full_name,business_name,role,phone,district,service_description,coverage_districts,is_verified")
      .single();
    if (error) throw error;
    return NextResponse.json({ partner: data });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to update business profile.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
