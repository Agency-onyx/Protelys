import Link from "next/link";
import { getSession } from "@/lib/session";
import { seDeconnecter } from "./actions";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { personne, estDirection, email } = await getSession();

  if (!personne) {
    return (
      <main className="mx-auto max-w-sm px-4 py-16">
        <p className="mb-4">
          Le compte {email} n&apos;est rattaché à personne de l&apos;équipe. Demande à un associé de t&apos;ajouter.
        </p>
        <form action={seDeconnecter}>
          <button className="rounded-lg bg-stone-200 px-4 py-2">Se déconnecter</button>
        </form>
      </main>
    );
  }

  const liens = [
    { href: "/terrain", libelle: "Terrain" },
    ...(estDirection
      ? [
          { href: "/affectation", libelle: "Rues" },
          { href: "/equipe", libelle: "Équipe" },
        ]
      : []),
  ];

  return (
    <div className="mx-auto min-h-dvh max-w-3xl pb-20">
      {children}
      <nav className="fixed inset-x-0 bottom-0 border-t border-stone-200 bg-white pb-[env(safe-area-inset-bottom)]">
        <div className="mx-auto flex max-w-3xl">
          {liens.map((l) => (
            <Link key={l.href} href={l.href} className="flex-1 py-3 text-center text-sm font-medium">
              {l.libelle}
            </Link>
          ))}
          <form action={seDeconnecter} className="flex-1">
            <button className="w-full py-3 text-center text-sm text-stone-500">Sortir</button>
          </form>
        </div>
      </nav>
    </div>
  );
}
