import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  basePath: "/agent-orchestra",
  images: { unoptimized: true },
};

export default nextConfig;
