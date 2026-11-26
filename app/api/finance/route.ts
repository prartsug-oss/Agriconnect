import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

type OrderRow = {
  id: string; buyer_id: string; seller_id: string; quantity: number;
  unit_price: number; total_amount: number; status: string; created_at: string;
  produce_listings?: { title?: string; unit?: string } | null;
};
type DeliveryRow = {
  id: string; order_id: string; buyer_id: string; seller_id: string;
  transporter_id: string | null; delivery_fee: number | null; status: string;
  created_at: string;
};

export async function GET() {
  try {
    const supabase = await createClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return NextResponse.json({ error: "Sign in to view financial activity." }, { status: 401 });

    const [{ data: profile, error: profileError }, { data: orders, error: ordersError }, { data: deliveries, error: deliveriesError }] = await Promise.all([
      supabase.from("profiles").select("role").eq("id", user.id).single(),
      supabase.from("orders").select("id,buyer_id,seller_id,quantity,unit_price,total_amount,status,created_at,produce_listings(title,unit)").or(`buyer_id.eq.${user.id},seller_id.eq.${user.id}`).order("created_at", { ascending: false }).limit(100),
      supabase.from("delivery_requests").select("id,order_id,buyer_id,seller_id,transporter_id,delivery_fee,status,created_at").order("created_at", { ascending: false }).limit(100),
    ]);
    if (profileError || !profile) throw profileError ?? new Error("Account profile not found.");
    if (ordersError) throw ordersError;
    if (deliveriesError) throw deliveriesError;

    const role = profile.role as string;
    const orderRows = (orders ?? []) as unknown as OrderRow[];
    const deliveryRows = (deliveries ?? []) as DeliveryRow[];
    const isSeller = role === "farmer" || role === "supplier";
    const isTransporter = role === "logistics";
    const relevantOrders = orderRows.filter(o => isSeller ? o.seller_id === user.id : o.buyer_id === user.id);
    const relevantDeliveries = deliveryRows.filter(d => isTransporter ? d.transporter_id === user.id : d.buyer_id === user.id || d.seller_id === user.id);

    const completedOrderValue = relevantOrders.filter(o => o.status === "completed").reduce((sum, o) => sum + Number(o.total_amount), 0);
    const openOrderValue = relevantOrders.filter(o => ["accepted", "in_transit"].includes(o.status)).reduce((sum, o) => sum + Number(o.total_amount), 0);
    const deliveryValue = relevantDeliveries.filter(d => ["assigned", "picked_up", "delivered"].includes(d.status)).reduce((sum, d) => sum + Number(d.delivery_fee ?? 0), 0);
    const deliveredFees = relevantDeliveries.filter(d => d.status === "delivered").reduce((sum, d) => sum + Number(d.delivery_fee ?? 0), 0);

    const entries = [
      ...relevantOrders.map(o => ({
        id: o.id, reference: o.id.slice(0, 8).toUpperCase(),
        description: o.produce_listings?.title || "Produce order",
        kind: isSeller ? "Produce sale" : "Produce purchase",
        amount: Number(o.total_amount), status: o.status, created_at: o.created_at,
      })),
      ...relevantDeliveries.filter(d => d.delivery_fee !== null).map(d => ({
        id: d.id, reference: d.id.slice(0, 8).toUpperCase(),
        description: "Delivery for order " + d.order_id.slice(0, 8).toUpperCase(),
        kind: isTransporter ? "Delivery earnings" : "Delivery fee",
        amount: Number(d.delivery_fee), status: d.status, created_at: d.created_at,
      })),
    ].sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

    return NextResponse.json({
      role,
      currency: "UGX",
      summary: {
        completed_order_value: completedOrderValue,
        open_order_value: openOrderValue,
        delivery_value: deliveryValue,
        delivered_fees: deliveredFees,
        completed_orders: relevantOrders.filter(o => o.status === "completed").length,
        open_orders: relevantOrders.filter(o => ["accepted", "in_transit"].includes(o.status)).length,
      },
      entries,
      note: "These are order and delivery values, not confirmed payments. AgriConnect has not connected a payment provider yet.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to load financial activity.";
    return NextResponse.json({ error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
