import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

function normalizeUgandaMobile(value: unknown) {
  if (typeof value !== "string") return null;
  const digits = value.replace(/[\s()-]/g, "");
  if (/^07[0-9]{8}$/.test(digits)) return "+256" + digits.slice(1);
  if (/^2567[0-9]{8}$/.test(digits)) return "+" + digits;
  if (/^\+2567[0-9]{8}$/.test(digits)) return digits;
  return null;
}

export async function GET() {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to view payment activity." }, { status: 401 });

    const { data, error } = await supabase
      .from("payment_attempts")
      .select("id,order_id,buyer_id,seller_id,provider,phone_number,amount,currency,status,provider_reference,provider_transaction_id,failure_reason,created_at,updated_at")
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw error;

    const payments = (data ?? []).map(payment => ({
      ...payment,
      phone_number: payment.buyer_id === user.id ? payment.phone_number : null,
    }));
    return NextResponse.json({ payments, note: "Awaiting-provider records are prepared locally and have not triggered a mobile-money prompt." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to load payment activity.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to prepare a payment." }, { status: 401 });

    const body = await request.json();
    const orderId = typeof body.order_id === "string" ? body.order_id : "";
    const provider = body.provider === "mtn_momo" || body.provider === "airtel_money" ? body.provider : "";
    const phone = normalizeUgandaMobile(body.phone_number);
    if (!orderId || !provider || !phone) {
      return NextResponse.json({ error: "Provide an order, choose MTN or Airtel Money, and enter a valid Uganda mobile number." }, { status: 400 });
    }

    const { data, error } = await supabase.rpc("create_mobile_money_payment", {
      p_order_id: orderId,
      p_provider: provider,
      p_phone_number: phone,
    });
    if (error) throw error;
    return NextResponse.json({
      payment: data,
      message: "Payment details saved. No money has been requested or transferred because the mobile-money gateway is not connected yet.",
    }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to prepare payment.";
    const status = message.includes("Sign in") ? 401 : message.includes("not found") ? 404 : message.includes("already exists") || message.includes("after the seller") ? 409 : message.includes("not configured") ? 503 : 400;
    return NextResponse.json({ error: message }, { status });
  }
}
