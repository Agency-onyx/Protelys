"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

// Connexion par e-mail. Le message contient un lien, et un code à six
// chiffres dès qu'un serveur d'envoi (SMTP) est branché sur Supabase.
// Le code est préférable sur iPhone : un lien s'ouvre dans Safari et non
// dans l'app ajoutée à l'écran d'accueil.
export default function Connexion() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [etape, setEtape] = useState<"email" | "code">("email");
  const [erreur, setErreur] = useState("");
  const [enCours, setEnCours] = useState(false);

  async function envoyer(e: React.FormEvent) {
    e.preventDefault();
    setErreur("");
    setEnCours(true);
    const { error } = await createClient().auth.signInWithOtp({
      email: email.trim(),
      options: { shouldCreateUser: false, emailRedirectTo: `${window.location.origin}/auth/callback` },
    });
    setEnCours(false);
    if (error) {
      setErreur(
        error.message.includes("Signups not allowed")
          ? "Cette adresse ne fait pas partie de l'équipe."
          : "Envoi impossible pour le moment. Réessaie dans une minute.",
      );
      return;
    }
    setEtape("code");
  }

  async function verifier(e: React.FormEvent) {
    e.preventDefault();
    setErreur("");
    setEnCours(true);
    const { error } = await createClient().auth.verifyOtp({
      email: email.trim(),
      token: code.trim(),
      type: "email",
    });
    setEnCours(false);
    if (error) {
      setErreur("Code incorrect ou expiré.");
      return;
    }
    router.replace("/terrain");
    router.refresh();
  }

  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center px-4">
      <h1 className="mb-6 text-2xl font-semibold">Connexion</h1>
      {etape === "email" ? (
        <form onSubmit={envoyer} className="space-y-3">
          <label className="block text-sm text-stone-600" htmlFor="email">
            Ton e-mail
          </label>
          <input
            id="email"
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-lg border border-stone-300 bg-white px-3 py-3 text-base"
          />
          <button
            disabled={enCours}
            className="w-full rounded-lg bg-green-900 py-3 font-medium text-white disabled:opacity-50"
          >
            Recevoir un code
          </button>
        </form>
      ) : (
        <form onSubmit={verifier} className="space-y-3">
          <p className="text-sm text-stone-600">
            E-mail envoyé à {email}. Ouvre le lien qu&apos;il contient, ou saisis ici le code s&apos;il y en a un.
          </p>
          <input
            inputMode="numeric"
            autoComplete="one-time-code"
            required
            value={code}
            onChange={(e) => setCode(e.target.value)}
            className="w-full rounded-lg border border-stone-300 bg-white px-3 py-3 text-center text-2xl tracking-widest"
          />
          <button
            disabled={enCours}
            className="w-full rounded-lg bg-green-900 py-3 font-medium text-white disabled:opacity-50"
          >
            Entrer
          </button>
          <button type="button" onClick={() => setEtape("email")} className="w-full py-2 text-sm text-stone-500">
            Changer d&apos;adresse
          </button>
        </form>
      )}
      {erreur && <p className="mt-4 text-sm text-red-700">{erreur}</p>}
    </main>
  );
}
