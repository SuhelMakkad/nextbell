import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const alt =
  "Nextbell. A little ahead. A lot more present. Join the Android closed test. Invited Google accounts only.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpenGraphImage() {
  const [font, icon] = await Promise.all([
    readFile(join(process.cwd(), "public/fonts/Manrope-SemiBold.ttf")),
    readFile(join(process.cwd(), "public/brand/icon.png")),
  ]);
  return new ImageResponse(
    <div
      style={{
        display: "flex",
        width: "100%",
        height: "100%",
        background: "#faf9f6",
        color: "#292c42",
        padding: 70,
        fontFamily: "Manrope",
        position: "relative",
      }}
    >
      <div style={{ display: "flex", flexDirection: "column", width: 850 }}>
        <div
          style={{
            display: "flex",
            fontSize: 30,
            fontWeight: 700,
            marginBottom: 45,
          }}
        >
          nextbell<span style={{ color: "#5856ce" }}>.</span>
        </div>
        <div style={{ fontSize: 74, letterSpacing: -4, lineHeight: 1.12 }}>
          A little ahead.
        </div>
        <div
          style={{
            fontSize: 74,
            letterSpacing: -4,
            lineHeight: 1.12,
            color: "#5856ce",
          }}
        >
          A lot more present.
        </div>
        <div
          style={{
            display: "flex",
            fontSize: 23,
            marginTop: 33,
            color: "#626578",
          }}
        >
          Thoughtful alarms for Google Calendar & Tasks.
        </div>
        <div
          style={{
            display: "flex",
            fontSize: 19,
            marginTop: 46,
            color: "#5856ce",
          }}
        >
          Android closed test · nextbell.org
        </div>
      </div>
      <div
        style={{
          display: "flex",
          position: "absolute",
          right: 42,
          top: 114,
          width: 210,
          height: 210,
          background: "#e6eee6",
          borderRadius: 110,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {/* ImageResponse renders an embedded image, not a browser image element. */}
        <img
          src={`data:image/png;base64,${icon.toString("base64")}`}
          width={142}
          height={142}
          alt=""
          style={{ borderRadius: 36, transform: "rotate(9deg)" }}
        />
      </div>
    </div>,
    {
      ...size,
      fonts: [{ name: "Manrope", data: font, style: "normal", weight: 600 }],
    },
  );
}
