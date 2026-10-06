"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

// Arrivée depuis le lien de connexion reçu par e-mail. Supabase peut
// renvoyer la session sous trois formes selon le réglage du projet :
// ?code=… (PKCE), ?token_hash=… ou #access_token=… (lien direct).
export default function Retour() {
  const [erreur, setErreur] = useState(false);

  useEffect(() => {
    (async () => {
      const supabase = createClient();
      const url = new URL(window.location.href);
      const code = url.searchParams.get("code");
      const tokenHash = url.searchParams.get("token_hash");
      const hash = new URLSearchParams(url.hash.replace(/^#/, ""));
      let ok = false;

      if (code) {
        ok = !(await supabase.auth.exchangeCodeForSession(code)).error;
      } else if (tokenHash) {
        const type = (url.searchParams.get("type") ?? "email") as "email" | "magiclink";
        ok = !(await supabase.auth.verifyOtp({ token_hash: tokenHash, type })).error;
      } else if (hash.get("access_token") && hash.get("refresh_token")) {
        ok = !(
          await supabase.auth.setSession({
            access_token: hash.get("access_token")!,
            refresh_token: hash.get("refresh_token")!,
          })
        ).error;
      } else {
        ok = !!(await supabase.auth.getSession()).data.session;
      }

      if (ok) window.location.replace("/terrain");
      else setErreur(true);
    })();
  }, []);

  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center px-4 text-center">
      {erreur ? (
        <>
          <p>Ce lien a expiré ou a déjà servi.</p>
          <a href="/connexion" className="mt-4 rounded-lg bg-green-900 py-3 font-medium text-white">
            Recevoir un nouveau lien
          </a>
        </>
      ) : (
        <p className="text-stone-500">Connexion…</p>
      )}
    </main>
  );
}
