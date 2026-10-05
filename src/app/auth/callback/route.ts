import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Arrivée depuis le lien de connexion reçu par e-mail.
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL("/terrain", request.url));
  }
  return NextResponse.redirect(new URL("/connexion?erreur=lien", request.url));
}
