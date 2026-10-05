import { exigerDirection } from "@/lib/session";
import Formulaire from "./formulaire";

const ROLES: Record<string, string> = {
  associe: "Associé",
  commercial: "Commercial",
  technicien: "Technicien",
  administratif: "Administratif",
};

type Ligne = {
  id: string;
  prenom: string;
  nom: string;
  email: string | null;
  user_id: string | null;
  postes: { role: string; date_debut: string; date_fin: string | null; cout_charge_mensuel: number }[];
};

export default async function Equipe() {
  const { supabase, jour } = await exigerDirection();
  const { data } = await supabase
    .from("personnes")
    .select("id, prenom, nom, email, user_id, postes(role, date_debut, date_fin, cout_charge_mensuel)")
    .is("scenario_id", null)
    .order("prenom");

  const euros = new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR", maximumFractionDigits: 0 });
  const date = (d: string) => new Date(d + "T12:00:00").toLocaleDateString("fr-FR");

  return (
    <main className="px-4 py-6">
      <h1 className="text-xl font-semibold">Équipe</h1>
      <ul className="mt-4 space-y-2">
        {((data ?? []) as Ligne[]).map((p) => (
          <li key={p.id} className="rounded-xl bg-white p-3 shadow-sm">
            <div className="flex items-baseline justify-between">
              <span className="font-medium">
                {p.prenom} {p.nom}
              </span>
              <span className="text-xs text-stone-500">{p.user_id ? "compte actif" : "jamais connecté"}</span>
            </div>
            <p className="text-xs text-stone-500">{p.email}</p>
            {p.postes.map((po, i) => {
              const enPoste = po.date_debut <= jour && (!po.date_fin || po.date_fin >= jour);
              return (
                <p key={i} className={`mt-1 text-sm ${enPoste ? "" : "text-stone-400"}`}>
                  {ROLES[po.role]} depuis le {date(po.date_debut)}
                  {po.date_fin && ` jusqu'au ${date(po.date_fin)}`} · {euros.format(po.cout_charge_mensuel)} chargé / mois
                </p>
              );
            })}
          </li>
        ))}
      </ul>

      <h2 className="mt-8 font-medium">Ajouter une personne</h2>
      <Formulaire jour={jour} roles={ROLES} />
    </main>
  );
}
