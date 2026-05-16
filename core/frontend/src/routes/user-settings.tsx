// /user-settings — per-user account management. org-scoped settings live
// under /settings/* and are unaffected by anything on this page.

import { createRoute } from "@tanstack/react-router";
import { useState } from "react";
import {
   useChangeEmail,
   useChangePassword,
   useMe,
   useRevokeSession,
   useSessions,
   useUpdateProfile,
} from "@/lib/queries";
import { gravatarUrl } from "@/lib/gravatar";
import { cn } from "@/lib/utils";
import { useTabSearch } from "@/lib/tab-search";
import { Button } from "@/components/ui/Button";
import { PageHeader } from "@/components/ui/PageHeader";
import { authedLayoutRoute } from "./_authed";

const TABS = ["profile", "security", "sessions", "2fa", "tokens"] as const;
type Tab = (typeof TABS)[number];

const TAB_LABELS: Record<Tab, string> = {
   profile: "Profile",
   security: "Security",
   sessions: "Sessions",
   "2fa": "2FA",
   tokens: "API tokens",
};

function UserSettingsPage() {
   const { tab, setTab } = useTabSearch(userSettingsRoute.id, TABS, "profile");

   return (
      <div className="px-10 py-8 max-w-3xl">
         <PageHeader
            title="User settings"
            description="Per-user account preferences. Org-level config lives under Settings."
            className="border-b-0 pb-0 mb-3"
         />

         <div className="flex items-center gap-1 border-b border-border">
            {TABS.map((t) => (
               <TabButton
                  key={t}
                  active={tab === t}
                  onClick={() => setTab(t)}
                  label={TAB_LABELS[t]}
               />
            ))}
         </div>

         <div className="mt-8">
            {tab === "profile" && <ProfileTab />}
            {tab === "security" && <SecurityTab />}
            {tab === "sessions" && <SessionsTab />}
            {tab === "2fa" && <TwoFactorTab />}
            {tab === "tokens" && <ApiTokensTab />}
         </div>
      </div>
   );
}

function ProfileTab() {
   const { data: me } = useMe();
   const update = useUpdateProfile();
   const [displayName, setDisplayName] = useState(me?.user.display_name ?? "");

   if (!me) return null;
   const avatar = gravatarUrl(me.user.email, 96);

   return (
      <div className="rounded-lg border border-border bg-surface divide-y divide-border">
         <Section title="Avatar">
            <div className="flex items-center gap-4">
               <img
                  src={avatar}
                  alt="profile avatar"
                  className="w-14 h-14 rounded-full border border-border bg-muted"
               />
               <div className="text-sm text-muted-foreground">
                  Pulled from{" "}
                  <a
                     href="https://gravatar.com"
                     target="_blank"
                     rel="noreferrer"
                     className="underline underline-offset-4 hover:text-foreground"
                  >
                     Gravatar
                  </a>{" "}
                  by email hash. Direct upload coming soon.
               </div>
            </div>
         </Section>

         <Section title="Display name">
            <form
               className="flex items-center gap-2 max-w-md"
               onSubmit={(e) => {
                  e.preventDefault();
                  update.mutate({ display_name: displayName || null });
               }}
            >
               <input
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder={me.user.email}
                  className="flex-1 rounded-md border border-border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring"
               />
               <Button type="submit" variant="primary" size="md" disabled={update.isPending}>
                  {update.isPending ? "Saving…" : "Save"}
               </Button>
            </form>
            <FormStatus mutation={update} />
         </Section>
      </div>
   );
}

function SecurityTab() {
   const { data: me } = useMe();
   const changePass = useChangePassword();
   const changeEmail = useChangeEmail();

   const [oldPass, setOldPass] = useState("");
   const [newPass, setNewPass] = useState("");
   const [confirmPass, setConfirmPass] = useState("");

   const [newEmail, setNewEmail] = useState("");
   const [emailPass, setEmailPass] = useState("");

   // me?.user.email guards the only access below; the layout shell
   // already gates this whole tree on me being defined.
   if (!me) return null;

   return (
      <div className="rounded-lg border border-border bg-surface divide-y divide-border">
         <Section
            title="Change password"
            description="On success, every other session for your account is revoked."
         >
            <form
               className="space-y-3 max-w-sm"
               onSubmit={(e) => {
                  e.preventDefault();
                  if (newPass !== confirmPass) return;
                  changePass.mutate(
                     { current_password: oldPass, new_password: newPass },
                     {
                        onSuccess: () => {
                           setOldPass("");
                           setNewPass("");
                           setConfirmPass("");
                        },
                     },
                  );
               }}
            >
               <Field
                  label="Current password"
                  type="password"
                  value={oldPass}
                  onChange={setOldPass}
                  autoComplete="current-password"
               />
               <Field
                  label="New password"
                  type="password"
                  value={newPass}
                  onChange={setNewPass}
                  autoComplete="new-password"
               />
               <Field
                  label="Confirm new password"
                  type="password"
                  value={confirmPass}
                  onChange={setConfirmPass}
                  autoComplete="new-password"
               />
               {newPass && confirmPass && newPass !== confirmPass && (
                  <div className="text-[11px] text-destructive">
                     New passwords don't match.
                  </div>
               )}
               <FormStatus mutation={changePass} />
               <Button
                  type="submit"
                  variant="primary"
                  size="sm"
                  disabled={
                     changePass.isPending ||
                     !oldPass ||
                     !newPass ||
                     newPass !== confirmPass
                  }
               >
                  {changePass.isPending ? "Updating…" : "Change password"}
               </Button>
            </form>
         </Section>

         <Section
            title="Change email"
            description={
               <>
                  Currently <span className="font-mono">{me.user.email}</span>.
                  Email verification ships in a later pass — see{" "}
                  <code>core/TODO.md</code>.
               </>
            }
         >
            <form
               className="space-y-3 max-w-sm"
               onSubmit={(e) => {
                  e.preventDefault();
                  changeEmail.mutate(
                     { new_email: newEmail, current_password: emailPass },
                     {
                        onSuccess: () => {
                           setNewEmail("");
                           setEmailPass("");
                        },
                     },
                  );
               }}
            >
               <Field
                  label="New email"
                  type="email"
                  value={newEmail}
                  onChange={setNewEmail}
                  autoComplete="email"
               />
               <Field
                  label="Current password"
                  type="password"
                  value={emailPass}
                  onChange={setEmailPass}
                  autoComplete="current-password"
               />
               <FormStatus mutation={changeEmail} />
               <Button
                  type="submit"
                  variant="primary"
                  size="sm"
                  disabled={changeEmail.isPending || !newEmail || !emailPass}
               >
                  {changeEmail.isPending ? "Updating…" : "Change email"}
               </Button>
            </form>
         </Section>
      </div>
   );
}

function SessionsTab() {
   const { data: sessions } = useSessions();
   const revoke = useRevokeSession();

   return (
      <div className="rounded-lg border border-border bg-surface divide-y divide-border overflow-hidden">
         {sessions?.length === 0 && (
            <div className="px-5 py-4 text-sm text-muted-foreground">
               No active sessions.
            </div>
         )}
         {sessions?.map((s) => (
            <div
               key={s.id}
               className="flex items-center gap-3 px-5 py-4 text-sm"
            >
               <div className="flex-1 min-w-0">
                  <div className="font-medium truncate">
                     {s.user_agent ?? "Unknown device"}
                     {s.is_current && (
                        <span className="ml-2 text-[10px] uppercase tracking-wider text-success">
                           Current
                        </span>
                     )}
                  </div>
                  <div className="mt-0.5 text-xs text-muted-foreground">
                     {s.ip ?? "?"} · last used {formatTs(s.last_used_at)}
                  </div>
               </div>
               {!s.is_current && (
                  <Button
                     type="button"
                     variant="ghost"
                     size="sm"
                     onClick={() => revoke.mutate(s.id)}
                     disabled={revoke.isPending}
                     className="text-muted-foreground hover:text-destructive"
                  >
                     Revoke
                  </Button>
               )}
            </div>
         ))}
      </div>
   );
}

function formatTs(ts: string | null): string {
   if (!ts) return "—";
   try {
      return new Date(ts).toLocaleString();
   } catch {
      return ts;
   }
}

// 2FA + API tokens are stubs; real impl tracked in core/TODO.md.

function TwoFactorTab() {
   return (
      <ComingSoon
         title="Two-factor authentication"
         body="TOTP-based 2FA (Google Authenticator, 1Password, etc) lands once the backend wires the secret-storage flow. Recovery codes will print at setup time — keep them somewhere safe."
      />
   );
}

function ApiTokensTab() {
   return (
      <ComingSoon
         title="API tokens"
         body="Personal access tokens for hitting the sf-voice API outside the browser. Will ship with per-token scopes, last-used timestamps, and one-click revocation."
      />
   );
}

function ComingSoon({ title, body }: { title: string; body: string }) {
   return (
      <div className="rounded-md border border-dashed border-border bg-muted/10 px-4 py-6 text-sm">
         <div className="font-medium">{title}</div>
         <p className="mt-2 text-muted-foreground max-w-md">{body}</p>
         <p className="mt-3 text-[11px] text-muted-foreground">
            Tracked under <code>core/TODO.md</code>.
         </p>
      </div>
   );
}

function Section({
   title,
   description,
   children,
   className,
}: {
   title: string;
   description?: React.ReactNode;
   children: React.ReactNode;
   className?: string;
}) {
   return (
      <section className={cn("px-5 py-4 space-y-3", className)}>
         <header>
            <h2 className="text-sm font-semibold tracking-tight">{title}</h2>
            {description && (
               <p className="mt-1 text-xs text-muted-foreground">
                  {description}
               </p>
            )}
         </header>
         {children}
      </section>
   );
}

function Field({
   label,
   type = "text",
   value,
   onChange,
   autoComplete,
}: {
   label: string;
   type?: string;
   value: string;
   onChange: (v: string) => void;
   autoComplete?: string;
}) {
   return (
      <label className="block">
         <div className="text-[11px] uppercase tracking-wider text-muted-foreground mb-1">
            {label}
         </div>
         <input
            type={type}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            autoComplete={autoComplete}
            className="w-full rounded-md border border-border bg-muted/20 px-3 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-info/60"
         />
      </label>
   );
}

function TabButton({
   active,
   onClick,
   label,
}: {
   active: boolean;
   onClick: () => void;
   label: string;
}) {
   return (
      <button
         type="button"
         onClick={onClick}
         className={cn(
            "px-4 py-2 text-sm -mb-px border-b-2 transition-colors",
            active
               ? "text-foreground border-foreground"
               : "text-muted-foreground hover:text-foreground border-transparent",
         )}
      >
         {label}
      </button>
   );
}

function FormStatus({
   mutation,
}: {
   mutation: {
      isError: boolean;
      isSuccess: boolean;
      error: unknown;
   };
}) {
   if (mutation.isError) {
      return (
         <div className="text-[11px] text-destructive">
            {(mutation.error as Error).message}
         </div>
      );
   }
   if (mutation.isSuccess) {
      return <div className="text-[11px] text-success">Saved.</div>;
   }
   return null;
}

type UserSettingsSearch = { tab?: Tab };

export const userSettingsRoute = createRoute({
   getParentRoute: () => authedLayoutRoute,
   path: "/user-settings",
   component: UserSettingsPage,
   validateSearch: (s: Record<string, unknown>): UserSettingsSearch => ({
      tab: (TABS as readonly string[]).includes((s.tab as string) ?? "")
         ? (s.tab as Tab)
         : undefined,
   }),
});
