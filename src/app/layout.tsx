import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Terrain",
  description: "Outil interne : prospection, contrats, pilotage",
  appleWebApp: { capable: true, title: "Terrain", statusBarStyle: "default" },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#14532d",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className="h-full antialiased">
      <body className="min-h-full bg-stone-100 text-stone-900">{children}</body>
    </html>
  );
}
