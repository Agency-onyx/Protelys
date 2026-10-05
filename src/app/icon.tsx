import { ImageResponse } from "next/og";

export const size = { width: 512, height: 512 };
export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          background: "#14532d",
          color: "#fefce8",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 300,
          fontWeight: 700,
        }}
      >
        T
      </div>
    ),
    size,
  );
}
