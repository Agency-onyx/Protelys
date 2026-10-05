"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function affecterRue(rueId: string, commercialId: string, jour: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("affecter_rue", {
    p_rue: rueId,
    p_commercial: commercialId,
    p_jour: jour,
  });
  if (error) return { ok: false as const, message: error.message };
  revalidatePath("/affectation");
  const r = (data as { affectees: number; deja_a_lui: number; tenues_par_autre: number }[])[0];
  const morceaux = [`${r.affectees} porte${r.affectees > 1 ? "s" : ""} affectée${r.affectees > 1 ? "s" : ""}`];
  if (r.deja_a_lui) morceaux.push(`${r.deja_a_lui} déjà à lui`);
  if (r.tenues_par_autre) morceaux.push(`${r.tenues_par_autre} tenues par un autre commercial`);
  return { ok: true as const, message: morceaux.join(", ") + "." };
}

export async function libererRue(rueId: string, commercialId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("liberer_rue", { p_rue: rueId, p_commercial: commercialId });
  if (error) return { ok: false as const, message: error.message };
  revalidatePath("/affectation");
  return { ok: true as const, message: `${data} porte${Number(data) > 1 ? "s" : ""} libérée${Number(data) > 1 ? "s" : ""}.` };
}
