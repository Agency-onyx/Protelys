"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export type EtatFormulaire = { ok: boolean; message: string } | null;

export async function ajouterPersonne(_: EtatFormulaire, form: FormData): Promise<EtatFormulaire> {
  const prenom = String(form.get("prenom") ?? "").trim();
  const nom = String(form.get("nom") ?? "").trim();
  const email = String(form.get("email") ?? "").trim().toLowerCase();
  const role = String(form.get("role") ?? "");
  const debut = String(form.get("debut") ?? "");
  const cout = Number(String(form.get("cout") ?? "0").replace(",", "."));

  if (!prenom || !nom || !email || !role || !debut || Number.isNaN(cout)) {
    return { ok: false, message: "Tous les champs sont obligatoires." };
  }

  // Les droits sont vérifiés par la base : seul un associé peut écrire ici.
  const supabase = await createClient();
  const { data: personne, error: e1 } = await supabase
    .from("personnes")
    .insert({ prenom, nom, email })
    .select("id")
    .single();
  if (e1) {
    return {
      ok: false,
      message: e1.code === "23505" ? "Cette adresse est déjà dans l'équipe." : e1.message,
    };
  }

  const { error: e2 } = await supabase
    .from("postes")
    .insert({ personne_id: personne.id, role, date_debut: debut, cout_charge_mensuel: cout });
  if (e2) {
    await supabase.from("personnes").delete().eq("id", personne.id);
    return { ok: false, message: e2.message };
  }

  // Compte de connexion. La base le rattache à la personne par l'e-mail.
  const { error: e3 } = await createAdminClient().auth.admin.createUser({ email, email_confirm: true });
  if (e3 && !/already/i.test(e3.message)) {
    return { ok: false, message: `Personne ajoutée, mais compte non créé : ${e3.message}` };
  }

  revalidatePath("/equipe");
  return { ok: true, message: `${prenom} peut se connecter avec ${email}.` };
}
