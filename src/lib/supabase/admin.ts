import "server-only";
import { createClient } from "@supabase/supabase-js";

// Clé secrète : ne sert qu'à créer les comptes de connexion de l'équipe.
export function createAdminClient() {
  return createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
