"use client";

import { useActionState } from "react";
import { ajouterPersonne } from "./actions";

const champ = "w-full rounded-lg border border-stone-300 bg-white px-3 py-2";

export default function Formulaire({ jour, roles }: { jour: string; roles: Record<string, string> }) {
  const [etat, action, enCours] = useActionState(ajouterPersonne, null);

  return (
    <form action={action} className="mt-3 space-y-2 rounded-xl bg-white p-3 shadow-sm">
      <div className="grid grid-cols-2 gap-2">
        <input name="prenom" placeholder="Prénom" required className={champ} />
        <input name="nom" placeholder="Nom" required className={champ} />
      </div>
      <input name="email" type="email" placeholder="E-mail de connexion" required className={champ} />
      <div className="grid grid-cols-2 gap-2">
        <select name="role" defaultValue="commercial" className={champ}>
          {Object.entries(roles).map(([v, l]) => (
            <option key={v} value={v}>
              {l}
            </option>
          ))}
        </select>
        <input name="debut" type="date" defaultValue={jour} required className={champ} />
      </div>
      <label className="block text-sm text-stone-600">
        Coût chargé mensuel (€)
        <input name="cout" inputMode="decimal" defaultValue="0" required className={`${champ} mt-1`} />
      </label>
      <button disabled={enCours} className="w-full rounded-lg bg-green-900 py-3 font-medium text-white disabled:opacity-50">
        Ajouter
      </button>
      {etat && <p className={`text-sm ${etat.ok ? "text-green-900" : "text-red-700"}`}>{etat.message}</p>}
    </form>
  );
}
