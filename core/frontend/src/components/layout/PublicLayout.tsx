// shell for unauthenticated pages — /signup, /login, /accept-invite.
// light theme, sf-voice.sh aesthetic: cream background, navy text,
// watercolor wash, paper grain.
//
// product pages (after login) use the dark `Layout`; both share the
// same semantic tokens, so this is the only file that controls light
// surfaces in the app.

import { Link, Outlet } from "@tanstack/react-router";
import { Watercolor } from "../brand/Watercolor";

export function PublicLayout() {
  return (
    <div className="relative min-h-screen bg-background text-foreground grain overflow-hidden">
      {/* watercolor washes — corners only, never centered */}
      <Watercolor
        hue="cyan"
        size={620}
        opacity={0.55}
        className="-top-32 -left-40"
      />
      <Watercolor
        hue="peach"
        size={520}
        opacity={0.5}
        className="top-1/3 -right-32"
      />
      <Watercolor
        hue="sand"
        size={420}
        opacity={0.4}
        className="-bottom-24 left-1/3"
      />

      <header className="relative z-10 px-8 py-5 flex items-center justify-between">
        <Link
          to="/"
          className="font-display text-xl tracking-tight text-foreground"
        >
          sf-voice
        </Link>
        <nav className="text-sm flex items-center gap-6 text-muted-foreground">
          <a
            href="https://sf-voice.sh"
            target="_blank"
            rel="noreferrer"
            className="hover:text-foreground transition-colors"
          >
            about
          </a>
          <Link
            to="/login"
            className="hover:text-foreground transition-colors"
          >
            sign in
          </Link>
        </nav>
      </header>

      <main className="relative z-10 flex items-center justify-center px-6 py-12 min-h-[calc(100vh-80px)]">
        <Outlet />
      </main>
    </div>
  );
}
