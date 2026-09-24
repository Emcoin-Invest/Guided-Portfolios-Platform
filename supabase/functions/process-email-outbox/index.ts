import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

    const { internal_token } = await req.json().catch(() => ({ internal_token: null }));
    if (!internal_token) return new Response("Unauthorized", { status: 401 });

    const publicClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey
    );

    const { data: secrets, error: secretError } = await publicClient.rpc(
      "get_email_runtime_secrets",
      { p_token: String(internal_token) }
    );

    if (secretError || !secrets?.resend_api_key) {
      return new Response("Unauthorized", { status: 401 });
    }

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: jobs, error: claimError } = await admin.rpc(
      "claim_email_outbox",
      { p_limit: 20 }
    );

    if (claimError) throw claimError;

    const results = [];

    for (const job of jobs ?? []) {
      try {
        const html = `<div style="font-family:Arial,sans-serif;max-width:640px;margin:auto;padding:24px">
          <div style="font-size:24px;font-weight:700;margin-bottom:20px">EmCoin</div>
          <h2 style="margin-bottom:12px">${escapeHtml(job.subject)}</h2>
          <div style="white-space:pre-wrap;line-height:1.6">${escapeHtml(job.body_text)}</div>
          <hr style="margin:28px 0;border:0;border-top:1px solid #ddd">
          <div style="font-size:12px;color:#666">EmCoin Guided Portfolios</div>
        </div>`;

        const resendResponse = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${secrets.resend_api_key}`,
            "Idempotency-Key": job.idempotency_key
          },
          body: JSON.stringify({
            from: secrets.from_email || "onboarding@resend.dev",
            to: [job.to_email],
            subject: job.subject,
            html
          })
        });

        const payload = await resendResponse.json().catch(() => ({}));

        if (!resendResponse.ok) {
          await admin.rpc("complete_email_outbox", {
            p_id: job.id,
            p_status: job.attempts >= 5 ? "failed" : "pending",
            p_provider_message_id: null,
            p_error: JSON.stringify(payload)
          });
          results.push({ id: job.id, status: "failed" });
          continue;
        }

        await admin.rpc("complete_email_outbox", {
          p_id: job.id,
          p_status: "sent",
          p_provider_message_id: payload.id ?? null,
          p_error: null
        });

        results.push({
          id: job.id,
          status: "sent",
          provider_message_id: payload.id ?? null
        });
      } catch (error) {
        await admin.rpc("complete_email_outbox", {
          p_id: job.id,
          p_status: job.attempts >= 5 ? "failed" : "pending",
          p_provider_message_id: null,
          p_error: error instanceof Error ? error.message : String(error)
        });
        results.push({ id: job.id, status: "failed" });
      }
    }

    return new Response(JSON.stringify({
      processed: results.length,
      results
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : String(error)
    }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
});

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
