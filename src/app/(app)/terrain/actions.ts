"use server";

import { createClient } from "@/lib/supabase/server";
import type { Statut } from "@/lib/statuts";

export async function noterVisite(etablissementId: string, statut: Statut) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("noter_visite", {
    p_etablissement: etablissementId,
    p_statut: statut,
  });
  return error ? { ok: false as const, erreur: error.message } : { ok: true as const };
}
