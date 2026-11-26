import { NextResponse } from "next/server";

export const runtime = "nodejs";

type ChatMessage = { role: "user" | "assistant"; content: string };

const demoReply = (question: string) => {
  const q = question.toLowerCase();
  if (/(tomato|leaf spot|spots on leaves|blight)/.test(q)) {
    return "Yellow or dark spots on tomato leaves can have several causes, including early blight, bacterial spot, nutrient stress or irregular watering. Check whether the spots have rings, whether they begin on older lower leaves, and whether the leaves are wet for long periods. Remove badly affected leaves, avoid overhead watering, improve airflow and do not compost diseased plants. This is a preliminary guide, not a confirmed diagnosis. Share a clear photo and your district for more specific guidance.";
  }
  if (/(maize|corn)/.test(q)) {
    return "For maize, check the crop's growth stage, soil moisture and leaf pattern before choosing a treatment. Yellowing can be linked to nitrogen deficiency, waterlogging, drought stress or disease. Inspect several plants across the field rather than one plant, and ask a local extension officer to confirm serious or spreading symptoms.";
  }
  return "I can help you investigate this farming question. Tell me the crop or animal, the symptoms, how long the problem has been happening and your district in Uganda. If you have a crop problem, describe which leaves or plant parts are affected. This demo guidance is general and should be confirmed with a qualified agricultural extension officer.";
};

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const question = typeof body.question === "string" ? body.question.trim() : "";
    const history = Array.isArray(body.history) ? body.history.slice(-8) as ChatMessage[] : [];
    if (!question) return NextResponse.json({ error: "Please enter a farming question." }, { status: 400 });
    if (question.length > 2000) return NextResponse.json({ error: "Please keep your question under 2,000 characters." }, { status: 400 });

    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      return NextResponse.json({ reply: demoReply(question), mode: "demo" });
    }

    const messages = [
      { role: "system", content: "You are AgriConnect AI, a careful agricultural information assistant for farmers in Uganda. Give practical, plain-language guidance. Ask clarifying questions when needed. Never claim certainty from symptoms alone, never invent live market prices or local outbreak reports, and recommend a qualified agricultural extension officer or veterinarian for serious cases. Mention safety precautions for pesticides and animal medicines. State when advice is general rather than a confirmed diagnosis." },
      ...history.filter((m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string").map((m) => ({ role: m.role, content: m.content.slice(0, 2000) })),
      { role: "user", content: question }
    ];

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: process.env.OPENAI_MODEL || "gpt-4o-mini", messages, temperature: 0.4, max_tokens: 500 }),
    });
    if (!response.ok) {
      const details = await response.text();
      console.error("OpenAI request failed:", response.status, details.slice(0, 500));
      return NextResponse.json({ error: "The AI service could not respond right now. Please try again shortly." }, { status: 502 });
    }
    const data = await response.json();
    const reply = data.choices?.[0]?.message?.content;
    if (typeof reply !== "string" || !reply.trim()) return NextResponse.json({ error: "The AI returned an empty response. Please try again." }, { status: 502 });
    return NextResponse.json({ reply: reply.trim(), mode: "live" });
  } catch (error) {
    console.error("AgriConnect AI error:", error);
    return NextResponse.json({ error: "Something went wrong while processing your question." }, { status: 500 });
  }
}
