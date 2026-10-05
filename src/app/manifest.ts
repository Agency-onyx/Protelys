import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Terrain",
    short_name: "Terrain",
    start_url: "/terrain",
    display: "standalone",
    background_color: "#f5f5f4",
    theme_color: "#14532d",
    icons: [{ src: "/icon", sizes: "512x512", type: "image/png" }],
  };
}
