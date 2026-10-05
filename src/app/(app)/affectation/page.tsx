import Link from "next/link";
import { exigerDirection } from "@/lib/session";
import Rues, { type Rue, type Commercial } from "./rues";

type TourneeLigne = {
  jour: string;
  commercial_id: string;
  rues: { nom_voie: string; code_insee: string };
};

export default async function Affectation({ searchParams }: { searchParams: Promise<{ commune?: string }> }) {
  const { supabase, jour } = await exigerDirection();
  const { commune: communeDemandee } = await searchParams;

  const { data: communes } = await supabase.from("communes").select("code_insee, nom").order("nom");
  if (!communes?.length) {
    return (
      <main className="px-4 py-8">
        <h1 className="text-xl font-semibold">Rues</h1>
        <p className="mt-2 text-stone-600">
          Aucune commune importée. Lance le script : <code>python3 scripts/import_sirene.py 93048</code>
        </p>
      </main>
    );
  }
  const commune = communes.find((c) => c.code_insee === communeDemandee) ?? communes[0];

  const [{ data: rues }, { data: postes }, { data: tournees }] = await Promise.all([
    supabase
      .from("v_rues")
      .select("id, nom_voie, portes, prio_a, prio_b, prio_c, libres, visitees, clients, derniere_visite_le, commerciaux")
      .eq("code_insee", commune.code_insee)
      .gt("portes", 0)
      .order("portes", { ascending: false }),
    supabase
      .from("postes")
      .select("role, date_debut, date_fin, personnes(id, prenom, nom)")
      .in("role", ["commercial", "associe"])
      .lte("date_debut", jour),
    supabase
      .from("tournees")
      .select("jour, commercial_id, rues(nom_voie, code_insee)")
      .gte("jour", jour)
      .order("jour"),
  ]);

  const commerciaux = new Map<string, Commercial>();
  for (const p of (postes ?? []) as unknown as {
    date_fin: string | null;
    personnes: { id: string; prenom: string; nom: string };
  }[]) {
    if (!p.date_fin || p.date_fin >= jour) {
      commerciaux.set(p.personnes.id, { id: p.personnes.id, nom: `${p.personnes.prenom} ${p.personnes.nom}` });
    }
  }
  const listeCommerciaux = [...commerciaux.values()].sort((a, b) => a.nom.localeCompare(b.nom));
  const nomDe = (id: string) => commerciaux.get(id)?.nom ?? "?";

  const planning = ((tournees ?? []) as unknown as TourneeLigne[]).map((t) => ({
    jour: t.jour,
    qui: nomDe(t.commercial_id),
    rue: t.rues.nom_voie,
  }));

  return (
    <main className="px-4 py-6">
      <h1 className="text-xl font-semibold">Rues</h1>

      {communes.length > 1 && (
        <div className="mt-3 flex gap-2 overflow-x-auto">
          {communes.map((c) => (
            <Link
              key={c.code_insee}
              href={`/affectation?commune=${c.code_insee}`}
              className={`whitespace-nowrap rounded-full px-3 py-1 text-sm ${
                c.code_insee === commune.code_insee ? "bg-green-900 text-white" : "bg-white"
              }`}
            >
              {c.nom}
            </Link>
          ))}
        </div>
      )}

      {planning.length > 0 && (
        <section className="mt-4 rounded-xl bg-white p-3 text-sm shadow-sm">
          <h2 className="mb-1 font-medium">Tournées prévues</h2>
          <ul className="space-y-0.5">
            {planning.map((t, i) => (
              <li key={i}>
                <span className="text-stone-500">
                  {new Date(t.jour + "T12:00:00").toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" })}
                </span>{" "}
                · {t.qui} · {t.rue}
              </li>
            ))}
          </ul>
        </section>
      )}

      <Rues
        rues={(rues ?? []) as Rue[]}
        commerciaux={listeCommerciaux}
        noms={Object.fromEntries(listeCommerciaux.map((c) => [c.id, c.nom]))}
        jour={jour}
      />
    </main>
  );
}
