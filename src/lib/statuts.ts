export type Statut =
  | "absent"
  | "ferme"
  | "refus"
  | "a_rappeler"
  | "interesse"
  | "signe"
  | "deja_equipe"
  | "hors_cible"
  | "introuvable";

// Les six premiers sont les boutons visibles, les trois autres sous « Autre ».
export const STATUTS: { valeur: Statut; libelle: string; classe: string; principal: boolean }[] = [
  { valeur: "absent", libelle: "Absent", classe: "bg-stone-200 text-stone-800", principal: true },
  { valeur: "ferme", libelle: "Fermé", classe: "bg-stone-300 text-stone-800", principal: true },
  { valeur: "refus", libelle: "Refus", classe: "bg-red-100 text-red-900", principal: true },
  { valeur: "a_rappeler", libelle: "À rappeler", classe: "bg-amber-100 text-amber-900", principal: true },
  { valeur: "interesse", libelle: "Intéressé", classe: "bg-sky-100 text-sky-900", principal: true },
  { valeur: "signe", libelle: "Signé", classe: "bg-green-700 text-white", principal: true },
  { valeur: "deja_equipe", libelle: "Déjà équipé", classe: "bg-violet-100 text-violet-900", principal: false },
  { valeur: "hors_cible", libelle: "Hors cible", classe: "bg-stone-200 text-stone-600", principal: false },
  { valeur: "introuvable", libelle: "Introuvable", classe: "bg-stone-200 text-stone-600", principal: false },
];

export const STATUT = Object.fromEntries(STATUTS.map((s) => [s.valeur, s])) as Record<
  Statut,
  (typeof STATUTS)[number]
>;
