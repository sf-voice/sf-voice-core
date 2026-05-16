// /accept-invite/$token — public preview + accept. when the user isn't
// authed yet, shows the org/role they've been invited to and a "sign in"
// link that preserves the token. when authed, an "accept" button.

import { useEffect } from "react";
import { Link, createRoute, useNavigate } from "@tanstack/react-router";
import {
  useAcceptInvite,
  useInvitePreview,
  useMe,
} from "@/lib/queries";
import { ApiError } from "@/lib/api";
import { publicLayoutRoute } from "./_public";

function AcceptInvitePage() {
  const { token } = acceptInviteRoute.useParams();
  const preview = useInvitePreview(token);
  const { data: me } = useMe();
  const accept = useAcceptInvite();
  const navigate = useNavigate();

  // when authed AND preview ok AND user's email matches, we still let
  // them click 'accept' manually — silently auto-accepting on land is
  // confusing. owners might want to verify the org name first.
  useEffect(() => {
    if (accept.isSuccess) {
      navigate({ to: "/" });
    }
  }, [accept.isSuccess, navigate]);

  if (preview.isLoading) {
    return <div className="text-sm text-muted-foreground">Loading invite…</div>;
  }

  if (preview.isError) {
    const err = preview.error;
    const notFound = err instanceof ApiError && err.status === 404;
    return (
      <Centered title={notFound ? "Invite not found" : "Couldn't load invite"}>
        <p className="text-sm text-muted-foreground">
          {notFound
            ? "This link is invalid or has been revoked. Ask whoever sent it for a fresh one."
            : err?.message ?? "Unknown error."}
        </p>
      </Centered>
    );
  }

  if (!preview.data) return null;
  const { org_name, role, email, expired, already_accepted } = preview.data;

  if (already_accepted) {
    return (
      <Centered title="Already accepted">
        <p className="text-sm text-muted-foreground">
          This invite is closed. If you need to rejoin {org_name}, ask an
          owner to send a new one.
        </p>
      </Centered>
    );
  }

  if (expired) {
    return (
      <Centered title="Invite expired">
        <p className="text-sm text-muted-foreground">
          This link expired. Ask {org_name} for a fresh one.
        </p>
      </Centered>
    );
  }

  const wrongAccount = me && me.user.email.toLowerCase() !== email.toLowerCase();

  return (
    <Centered
      title={`Join ${org_name}`}
      subtitle={`You've been invited as ${role}.`}
    >
      <div className="rounded-md border border-border bg-background p-4 text-sm space-y-1">
        <KV label="Org" value={org_name} />
        <KV label="Role" value={role} />
        <KV label="Email" value={email} mono />
      </div>

      {!me ? (
        <div className="space-y-2">
          <p className="text-sm text-muted-foreground">
            Sign in or create an account using <strong>{email}</strong>{" "}
            to accept.
          </p>
          <Link
            to="/login"
            className="block w-full rounded-md bg-primary text-primary-foreground py-2.5 text-sm font-medium text-center hover:opacity-90"
          >
            Sign in →
          </Link>
          <Link
            to="/signup"
            className="block w-full text-center text-sm text-muted-foreground hover:text-foreground py-1.5"
          >
            New here? Create an account
          </Link>
        </div>
      ) : wrongAccount ? (
        <div className="rounded-md border border-destructive/50 bg-destructive/10 p-3 text-sm text-destructive">
          You're signed in as <strong>{me.user.email}</strong>, but this
          invite is for <strong>{email}</strong>. Sign out, then come back
          to this link.
        </div>
      ) : (
        <button
          type="button"
          disabled={accept.isPending}
          onClick={() => accept.mutate(token)}
          className="w-full rounded-md bg-primary text-primary-foreground py-2.5 text-sm font-medium hover:opacity-90 disabled:opacity-40"
        >
          {accept.isPending ? "Accepting…" : `Accept and switch to ${org_name}`}
        </button>
      )}

      {accept.isError && (
        <p className="text-xs text-destructive text-center">
          {accept.error.message}
        </p>
      )}
    </Centered>
  );
}

function Centered({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="w-full max-w-md space-y-5">
      <header className="text-center">
        <h1 className="font-display text-3xl tracking-tight text-foreground">
          {title}
        </h1>
        {subtitle && (
          <p className="mt-2 text-sm text-muted-foreground">{subtitle}</p>
        )}
      </header>
      {children}
    </div>
  );
}

function KV({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div className="flex items-baseline gap-3">
      <span className="text-sm uppercase tracking-wider text-muted-foreground font-medium w-14 shrink-0">
        {label}
      </span>
      <span
        className={mono ? "font-mono text-foreground" : "text-foreground"}
      >
        {value}
      </span>
    </div>
  );
}

export const acceptInviteRoute = createRoute({
  getParentRoute: () => publicLayoutRoute,
  path: "/accept-invite/$token",
  component: AcceptInvitePage,
});
