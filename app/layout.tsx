import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AgriConnect | Grow together",
  description: "A smarter marketplace connecting farmers, buyers and agricultural businesses across Uganda.",
  applicationName: "AgriConnect",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
