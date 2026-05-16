// /settings/team — list members, invite by email, manage pending invites.
// v1 has no SMTP: creating an invite returns a URL the owner copies and
// shares manually. invite_url is mirrored in a "copy" button on the row.

import { useState } from "react";
import { createRoute } from "@tanstack/react-router";
import { formatDistanceToNow } from "date-fns";
import {
  useCreateInvite,
  useInvites,
  useMembers,
  useRevokeInvite,
} from "@/lib/queries";
import type { InviteDto, MemberDto } from "@/lib/api";
import { cn } from "@/lib/utils";
import { authedLayoutRoute } from "./_authed";

function SettingsTeamPage() {
  const { data: members } = useMembers();
  const { data: invites } = useInvites();

  const active = (invites ?? []).filter((i) => !i.accepted_at);
  const accepted = (invites ?? []).filter((i) => i.accepted_at);

  return (
    <div className="px-10 py-8 max-w-3xl">
      <header className="mb-6">
        <h1 className="text-lg font-semibold tracking-tight">Team</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Invite teammates to this org. v1 doesn't send email — copy the
          generated link and share it however you like.
        </p>
      </header>

      <section className="space-y-3">
        <SectionHeading>Invite by email</SectionHeading>
        <InviteForm />
      </section>

      <section className="mt-10 space-y-3">
        <SectionHeading>Members ({members?.length ?? 0})</SectionHeading>
        <MembersList members={members} />
      </section>

      {active.length > 0 && (
        <section className="mt-10 space-y-3">
          <SectionHeading>Pending invites</SectionHeading>
          <InvitesList invites={active} />
        </section>
      )}

      {accepted.length > 0 && (
        <section className="mt-10 space-y-3">
          <SectionHeading>Accepted</SectionHeading>
          <InvitesList invites={accepted} acceptedView />
        </section>
      )}
    </div>
  );
}

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-sm uppercase tracking-wider text-muted-foreground font-medium">
      {children}
    </h2>
  );
}

function InviteForm() {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"owner" | "member">("member");
  const create = useCreateInvite();

  return (
    <form
      className="flex items-end gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        if (!email) return;
        create.mutate(
          { email, role },
          {
            onSuccess: () => setEmail(""),
          },
        );
      }}
    >
      <label className="flex-1 block">
        <div className="text-sm text-muted-foreground font-medium">Email</div>
        <input
          type="email"
          required
          value={email}
          placeholder="teammate@acme.com"
          onChange={(e) => setEmail(e.target.value)}
          className="mt-1 w-full rounded-md border border-border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
        />
      </label>
      <label className="block">
        <div className="text-sm text-muted-foreground font-medium">Role</div>
        <select
          value={role}
          onChange={(e) => setRole(e.target.value as "owner" | "member")}
          className="mt-1 rounded-md border border-border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
        >
          <option value="member">Member</option>
          <option value="owner">Owner</option>
        </select>
      </label>
      <button
        type="submit"
        disabled={create.isPending || !email}
        className="rounded-md bg-primary text-primary-foreground px-3 py-1.5 text-sm font-medium hover:opacity-90 disabled:opacity-40"
      >
        {create.isPending ? "Creating…" : "Create invite"}
      </button>
    </form>
  );
}

function MembersList({ members }: { members: MemberDto[] | undefined }) {
  if (!members || members.length === 0) {
    return <p className="text-sm text-muted-foreground">No members yet.</p>;
  }
  return (
    <div className="rounded-md border border-border overflow-hidden">
      <table className="w-full text-sm">
        <tbody>
          {members.map((m) => (
            <tr key={m.user_id} className="border-b border-border/50 last:border-b-0">
              <td className="px-4 py-2 text-foreground">{m.email}</td>
              <td className="px-4 py-2 text-muted-foreground text-sm">
                {m.role[0].toUpperCase() + m.role.slice(1)}
              </td>
              <td className="px-4 py-2 text-muted-foreground text-sm text-right">
                Joined {formatDistanceToNow(new Date(m.joined_at), { addSuffix: true })}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function InvitesList({
  invites,
  acceptedView,
}: {
  invites: InviteDto[];
  acceptedView?: boolean;
}) {
  return (
    <div className="rounded-md border border-border overflow-hidden">
      <table className="w-full text-sm">
        <tbody>
          {invites.map((i) => (
            <InviteRow key={i.id} invite={i} acceptedView={acceptedView} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function InviteRow({
  invite,
  acceptedView,
}: {
  invite: InviteDto;
  acceptedView?: boolean;
}) {
  const [copied, setCopied] = useState(false);
  const revoke = useRevokeInvite();
  return (
    <tr className="border-b border-border/50 last:border-b-0 align-top">
      <td className="px-4 py-2.5">
        <div className="text-foreground text-sm">{invite.email}</div>
        <div className="text-sm text-muted-foreground">
          {invite.role[0].toUpperCase() + invite.role.slice(1)}
          {acceptedView
            ? ` · Accepted ${formatDistanceToNow(new Date(invite.accepted_at!), { addSuffix: true })}`
            : ` · Expires ${formatDistanceToNow(new Date(invite.expires_at), { addSuffix: true })}`}
        </div>
        {!acceptedView && (
          <div className="mt-1 font-mono text-xs text-muted-foreground break-all">
            {invite.accept_url}
          </div>
        )}
      </td>
      {!acceptedView && (
        <td className="px-4 py-2.5 text-right whitespace-nowrap">
          <button
            type="button"
            onClick={() => {
              navigator.clipboard.writeText(invite.accept_url);
              setCopied(true);
              setTimeout(() => setCopied(false), 1500);
            }}
            className={cn(
              "text-sm px-2 py-1 rounded border border-border hover:bg-muted/40",
              copied && "text-success border-success",
            )}
          >
            {copied ? "Copied" : "Copy link"}
          </button>
          <button
            type="button"
            onClick={() => revoke.mutate(invite.id)}
            disabled={revoke.isPending}
            className="ml-2 text-sm px-2 py-1 rounded border border-border hover:bg-destructive/10 hover:text-destructive"
          >
            Revoke
          </button>
        </td>
      )}
    </tr>
  );
}

export const settingsTeamRoute = createRoute({
  getParentRoute: () => authedLayoutRoute,
  path: "/settings/team",
  component: SettingsTeamPage,
});
