import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type Role = "associe" | "commercial" | "technicien" | "administratif";

export function aujourdhuiParis(): string {
  // AAAA-MM-JJ à l'heure de Paris
  return new Intl.DateTimeFormat("fr-CA", { timeZone: "Europe/Paris" }).format(new Date());
}

export async function getSession() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/connexion");

  const { data: personne } = await supabase
    .from("personnes")
    .select("id, prenom, nom")
    .eq("user_id", user.id)
    .is("scenario_id", null)
    .maybeSingle();

  const jour = aujourdhuiParis();
  let roles: Role[] = [];
  if (personne) {
    const { data: postes } = await supabase
      .from("postes")
      .select("role, date_debut, date_fin")
      .eq("personne_id", personne.id)
      .lte("date_debut", jour);
    roles = (postes ?? [])
      .filter((p) => !p.date_fin || p.date_fin >= jour)
      .map((p) => p.role as Role);
  }

  return {
    supabase,
    email: user.email ?? "",
    personne: personne as { id: string; prenom: string; nom: string } | null,
    roles,
    estDirection: roles.includes("associe") || roles.includes("administratif"),
    jour,
  };
}

export async function exigerDirection() {
  const s = await getSession();
  if (!s.estDirection) redirect("/terrain");
  return s;
}
