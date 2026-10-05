import Link from "next/link";
import { getSession } from "@/lib/session";
import type { Statut } from "@/lib/statuts";
import Portes, { type Porte } from "./portes";

type Tournee = { rue_id: string; rues: { nom_voie: string; communes: { nom: string } } };

function jourParis(iso: string | null) {
  if (!iso) return null;
  return new Intl.DateTimeFormat("fr-CA", { timeZone: "Europe/Paris" }).format(new Date(iso));
}

export default async function Terrain({ searchParams }: { searchParams: Promise<{ rue?: string }> }) {
  const { supabase, personne, jour } = await getSession();
  const { rue: rueDemandee } = await searchParams;

  const { data: tourneesBrutes } = await supabase
    .from("tournees")
    .select("rue_id, rues(nom_voie, communes(nom))")
    .eq("jour", jour)
    .eq("commercial_id", personne!.id);
  const tournees = (tourneesBrutes ?? []) as unknown as Tournee[];

  const dateLisible = new Intl.DateTimeFormat("fr-FR", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: "Europe/Paris",
  }).format(new Date());

  if (tournees.length === 0) {
    return (
      <main className="px-4 py-8">
        <p className="text-sm capitalize text-stone-500">{dateLisible}</p>
        <h1 className="mt-1 text-xl font-semibold">Pas de rue aujourd&apos;hui</h1>
        <p className="mt-2 text-stone-600">Un associé doit t&apos;affecter une rue pour la journée.</p>
      </main>
    );
  }

  const rueId = tournees.find((t) => t.rue_id === rueDemandee)?.rue_id ?? tournees[0].rue_id;
  const tournee = tournees.find((t) => t.rue_id === rueId)!;

  const { data: lignes } = await supabase
    .from("v_prospects")
    .select(
      "id, nom, enseigne, numero, indice_repetition, complement_adresse, priorite, dernier_statut, derniere_visite_le, nb_visites, est_client",
    )
    .eq("rue_id", rueId)
    .eq("commercial_id", personne!.id)
    .eq("actif_sirene", true)
    .neq("priorite", "chaine")
    .order("ordre_cote")
    .order("ordre_numero", { nullsFirst: false })
    .order("indice_repetition", { nullsFirst: true });

  const portes: Porte[] = (lignes ?? []).map((l) => ({
    id: l.id,
    nom: l.enseigne || l.nom,
    raison: l.enseigne ? l.nom : null,
    adresse: [l.numero, l.indice_repetition].filter(Boolean).join(" ") || l.complement_adresse || "s/n",
    priorite: l.priorite,
    dernierStatut: l.dernier_statut as Statut | null,
    faiteAujourdhui: jourParis(l.derniere_visite_le) === jour,
    nbVisites: l.nb_visites,
    estClient: l.est_client,
  }));

  return (
    <main>
      <header className="sticky top-0 z-10 border-b border-stone-200 bg-stone-100/95 px-4 pb-2 pt-4 backdrop-blur">
        <p className="text-sm capitalize text-stone-500">{dateLisible}</p>
        <h1 className="text-xl font-semibold">
          {tournee.rues.nom_voie.toLowerCase().replace(/(^|\s)\S/g, (c) => c.toUpperCase())}
        </h1>
        <p className="text-sm text-stone-500">{tournee.rues.communes.nom}</p>
        {tournees.length > 1 && (
          <div className="mt-2 flex gap-2 overflow-x-auto">
            {tournees.map((t) => (
              <Link
                key={t.rue_id}
                href={`/terrain?rue=${t.rue_id}`}
                className={`whitespace-nowrap rounded-full px-3 py-1 text-sm ${
                  t.rue_id === rueId ? "bg-green-900 text-white" : "bg-white"
                }`}
              >
                {t.rues.nom_voie}
              </Link>
            ))}
          </div>
        )}
      </header>
      <Portes key={rueId} portes={portes} />
    </main>
  );
}
