"use client";

import { useState, useTransition } from "react";
import { STATUT, STATUTS, type Statut } from "@/lib/statuts";
import { noterVisite } from "./actions";

export type Porte = {
  id: string;
  nom: string;
  raison: string | null;
  adresse: string;
  priorite: "A" | "B" | "C";
  dernierStatut: Statut | null;
  faiteAujourdhui: boolean;
  nbVisites: number;
  estClient: boolean;
};

const PRIO: Record<Porte["priorite"], string> = {
  A: "bg-green-800 text-white",
  B: "bg-green-200 text-green-900",
  C: "bg-stone-200 text-stone-600",
};

export default function Portes({ portes: initiales }: { portes: Porte[] }) {
  const [portes, setPortes] = useState(initiales);
  const [ouverte, setOuverte] = useState<string | null>(
    initiales.find((p) => !p.faiteAujourdhui)?.id ?? null,
  );
  const [autres, setAutres] = useState(false);
  const [erreur, setErreur] = useState("");
  const [, startTransition] = useTransition();

  const faites = portes.filter((p) => p.faiteAujourdhui).length;

  function noter(porte: Porte, statut: Statut) {
    setErreur("");
    const avant = portes;
    const maj = portes.map((p) =>
      p.id === porte.id
        ? {
            ...p,
            dernierStatut: statut,
            nbVisites: p.faiteAujourdhui ? p.nbVisites : p.nbVisites + 1,
            faiteAujourdhui: true,
          }
        : p,
    );
    setPortes(maj);
    setAutres(false);
    // Porte suivante non faite, dans l'ordre de marche
    const i = maj.findIndex((p) => p.id === porte.id);
    const suivante = [...maj.slice(i + 1), ...maj.slice(0, i)].find((p) => !p.faiteAujourdhui);
    setOuverte(suivante?.id ?? null);

    startTransition(async () => {
      const r = await noterVisite(porte.id, statut);
      if (!r.ok) {
        setPortes(avant);
        setOuverte(porte.id);
        setErreur(r.erreur);
      }
    });
  }

  return (
    <>
      <div className="px-4 py-3">
        <div className="flex items-baseline justify-between text-sm">
          <span>
            <strong className="text-lg">{faites}</strong> / {portes.length} portes aujourd&apos;hui
          </span>
          <span className="text-stone-500">impairs, puis pairs au retour</span>
        </div>
        <div className="mt-2 h-2 overflow-hidden rounded-full bg-stone-200">
          <div
            className="h-full bg-green-800 transition-all"
            style={{ width: `${portes.length ? (faites / portes.length) * 100 : 0}%` }}
          />
        </div>
        {erreur && <p className="mt-2 rounded bg-red-100 px-3 py-2 text-sm text-red-900">{erreur}</p>}
      </div>

      <ul className="space-y-2 px-4 pb-6">
        {portes.map((p) => {
          const estOuverte = ouverte === p.id;
          const st = p.dernierStatut ? STATUT[p.dernierStatut] : null;
          return (
            <li
              key={p.id}
              className={`rounded-xl bg-white shadow-sm ${p.faiteAujourdhui && !estOuverte ? "opacity-60" : ""}`}
            >
              <button
                onClick={() => {
                  setOuverte(estOuverte ? null : p.id);
                  setAutres(false);
                }}
                className="flex w-full items-center gap-3 px-3 py-3 text-left"
              >
                <span className="w-12 shrink-0 text-lg font-semibold tabular-nums">{p.adresse}</span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-medium">{p.nom}</span>
                  {p.raison && <span className="block truncate text-xs text-stone-500">{p.raison}</span>}
                </span>
                {p.estClient && <span className="rounded bg-green-700 px-2 py-0.5 text-xs text-white">Client</span>}
                {st && <span className={`rounded px-2 py-0.5 text-xs ${st.classe}`}>{st.libelle}</span>}
                <span className={`rounded px-1.5 py-0.5 text-xs font-bold ${PRIO[p.priorite]}`}>{p.priorite}</span>
              </button>

              {estOuverte && (
                <div className="border-t border-stone-100 p-3">
                  {p.nbVisites > 0 && (
                    <p className="mb-2 text-xs text-stone-500">
                      {p.nbVisites} visite{p.nbVisites > 1 ? "s" : ""}
                      {st ? ` · dernier statut : ${st.libelle}` : ""}
                    </p>
                  )}
                  <div className="grid grid-cols-3 gap-2">
                    {STATUTS.filter((s) => s.principal || autres).map((s) => (
                      <button
                        key={s.valeur}
                        onClick={() => noter(p, s.valeur)}
                        className={`rounded-lg py-4 text-sm font-medium active:scale-95 ${s.classe}`}
                      >
                        {s.libelle}
                      </button>
                    ))}
                  </div>
                  {!autres && (
                    <button onClick={() => setAutres(true)} className="mt-2 w-full py-2 text-sm text-stone-500">
                      Autre…
                    </button>
                  )}
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </>
  );
}
