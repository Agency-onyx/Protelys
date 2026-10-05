"use client";

import { useState, useTransition } from "react";
import { affecterRue, libererRue } from "./actions";

export type Rue = {
  id: string;
  nom_voie: string;
  portes: number;
  prio_a: number;
  prio_b: number;
  prio_c: number;
  libres: number;
  visitees: number;
  clients: number;
  derniere_visite_le: string | null;
  commerciaux: string[];
};
export type Commercial = { id: string; nom: string };

export default function Rues({
  rues,
  commerciaux,
  noms,
  jour,
}: {
  rues: Rue[];
  commerciaux: Commercial[];
  noms: Record<string, string>;
  jour: string;
}) {
  const [filtre, setFiltre] = useState("");
  const [ouverte, setOuverte] = useState<string | null>(null);
  const [qui, setQui] = useState(commerciaux[0]?.id ?? "");
  const [quand, setQuand] = useState(jour);
  const [message, setMessage] = useState<{ rue: string; texte: string; ok: boolean } | null>(null);
  const [enCours, startTransition] = useTransition();

  const visibles = rues.filter((r) => r.nom_voie.toLowerCase().includes(filtre.toLowerCase()));

  function lancer(rue: string, action: () => Promise<{ ok: boolean; message: string }>) {
    startTransition(async () => {
      const r = await action();
      setMessage({ rue, texte: r.message, ok: r.ok });
    });
  }

  return (
    <>
      <input
        placeholder="Chercher une rue"
        value={filtre}
        onChange={(e) => setFiltre(e.target.value)}
        className="mt-4 w-full rounded-lg border border-stone-300 bg-white px-3 py-2"
      />
      <p className="mt-2 text-xs text-stone-500">
        Les chaînes sont exclues. A : déclare un salarié, B : a une enseigne, C : le reste.
      </p>

      <ul className="mt-3 space-y-2">
        {visibles.map((r) => (
          <li key={r.id} className="rounded-xl bg-white shadow-sm">
            <button
              onClick={() => setOuverte(ouverte === r.id ? null : r.id)}
              className="flex w-full items-center gap-3 px-3 py-3 text-left"
            >
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">{r.nom_voie}</span>
                <span className="block text-xs text-stone-500">
                  {r.portes} portes · A {r.prio_a} · B {r.prio_b} · C {r.prio_c}
                  {r.visitees > 0 && ` · ${r.visitees} visitées`}
                  {r.clients > 0 && ` · ${r.clients} clients`}
                </span>
              </span>
              {r.commerciaux.length > 0 ? (
                <span className="text-right text-xs text-green-900">
                  {r.commerciaux.map((c) => noms[c] ?? "?").join(", ")}
                  {r.libres > 0 && <span className="block text-stone-500">{r.libres} libres</span>}
                </span>
              ) : (
                <span className="text-xs text-stone-400">libre</span>
              )}
            </button>

            {ouverte === r.id && (
              <div className="space-y-3 border-t border-stone-100 p-3">
                <div className="grid grid-cols-2 gap-2">
                  <select
                    value={qui}
                    onChange={(e) => setQui(e.target.value)}
                    className="rounded-lg border border-stone-300 bg-white px-2 py-2"
                  >
                    {commerciaux.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.nom}
                      </option>
                    ))}
                  </select>
                  <input
                    type="date"
                    value={quand}
                    min={jour}
                    onChange={(e) => setQuand(e.target.value)}
                    className="rounded-lg border border-stone-300 bg-white px-2 py-2"
                  />
                </div>
                <button
                  disabled={enCours || !qui}
                  onClick={() => lancer(r.id, () => affecterRue(r.id, qui, quand))}
                  className="w-full rounded-lg bg-green-900 py-3 font-medium text-white disabled:opacity-50"
                >
                  Affecter la rue pour ce jour
                </button>
                {r.commerciaux.map((c) => (
                  <button
                    key={c}
                    disabled={enCours}
                    onClick={() => lancer(r.id, () => libererRue(r.id, c))}
                    className="w-full rounded-lg bg-stone-100 py-2 text-sm disabled:opacity-50"
                  >
                    Retirer la rue à {noms[c] ?? "?"}
                  </button>
                ))}
                {message?.rue === r.id && (
                  <p className={`text-sm ${message.ok ? "text-green-900" : "text-red-700"}`}>{message.texte}</p>
                )}
              </div>
            )}
          </li>
        ))}
      </ul>
    </>
  );
}
