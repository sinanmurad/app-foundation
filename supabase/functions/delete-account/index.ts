// ============================================================
// Hesap Silme Edge Function (App Store zorunluluğu)
// ============================================================
// Kullanıcı kendi JWT'si ile KENDİ hesabını siler. service_role anahtarı
// asla uygulamaya girmez, sadece bu sunucu fonksiyonunda kalır.
//
// Deploy: supabase functions deploy delete-account
//
// Yeni tablo eklediğinde USER_TABLES listesine ekle. (auth.users'a
// "on delete cascade" ile bağlı tablolar zaten otomatik silinir; liste
// cascade olmayan tablolar için güvenlik ağıdır.)
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const USER_TABLES = ["items"];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Yetkilendirme başlığı eksik" }, 401);

    const jwt = authHeader.replace("Bearer ", "");
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: { user }, error: userError } = await adminClient.auth.getUser(jwt);
    if (userError || !user) return json({ error: "Geçersiz oturum" }, 401);

    for (const table of USER_TABLES) {
      const { error } = await adminClient.from(table).delete().eq("user_id", user.id);
      if (error) console.error(`delete-account: ${table}: ${error.message}`);
    }

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);
    if (deleteError) return json({ error: deleteError.message }, 400);

    return json({ success: true }, 200);
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});
