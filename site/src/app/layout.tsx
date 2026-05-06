import type { Metadata } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const jetBrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Agent Orchestra 🎼 — Conduct AI Fleets in Concert",
  description:
    "Agent Orchestra cues visible Terminal Stampede commander sections, lets them collaborate through append-only ledger motifs, watches runs with Agent Pulse, and scores repeatability with Shadow Score and Fleet Scorecard.",
  metadataBase: new URL("https://dubsopenhub.github.io"),
  openGraph: {
    title: "Agent Orchestra 🎼 — Conduct AI Fleets in Concert",
    description:
      "Agent Orchestra cues visible Terminal Stampede commander sections, lets them collaborate through append-only ledger motifs, watches runs with Agent Pulse, and scores repeatability with Shadow Score and Fleet Scorecard.",
    url: "https://dubsopenhub.github.io/agent-orchestra/",
    siteName: "Agent Orchestra",
    type: "website",
    images: [
      {
        url: "/agent-orchestra/og-image.svg",
        width: 1200,
        height: 630,
        alt: "Agent Orchestra — conduct multi-agent fleets from the terminal",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Agent Orchestra 🎼 — Conduct AI Fleets in Concert",
    description:
      "Cue visible commander sections, live collaboration ledger motifs, Agent Pulse telemetry, and sealed run decisions.",
    images: ["/agent-orchestra/og-image.svg"],
  },
  keywords: [
    "AI agents",
    "Copilot CLI",
    "Terminal Stampede",
    "Agent Pulse",
    "agent orchestration",
    "Shadow Score",
    "multi-agent systems",
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${inter.variable} ${jetBrainsMono.variable}`}>
        {children}
      </body>
    </html>
  );
}
