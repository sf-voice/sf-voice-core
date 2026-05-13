// /signup — the front door. cream background + watercolor wash + playfair
// hero copy borrowed from sf-voice.sh. one-step signup: email + password
// + optional org name creates user + org + session and lands the user on /.

import { useState } from "react";
import { Link, createRoute, useNavigate } from "@tanstack/react-router";
import { useSignup } from "@/lib/queries";
import { ApiError } from "@/lib/api";
import { publicLayoutRoute } from "./_public";

function SignupPage() {
  const navigate = useNavigate();
  const signup = useSignup();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [orgName, setOrgName] = useState("");

  return (
    <div className="w-full max-w-md">
      <header className="mb-8 text-center">
        <h1 className="font-display text-4xl tracking-tight text-foreground">
          start hearing what others miss.
        </h1>
        <p className="mt-3 text-muted-foreground text-sm leading-relaxed">
          two minutes to set up. you'll connect an s3 bucket and we'll
          surface the moments your voice agent fumbled.
        </p>
      </header>

      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          signup.mutate(
            { email, password, org_name: orgName || undefined },
            { onSuccess: () => navigate({ to: "/" }) },
          );
        }}
      >
        <Field
          label="email"
          type="email"
          value={email}
          onChange={setEmail}
          required
          autoFocus
        />
        <Field
          label="password"
          type="password"
          value={password}
          onChange={setPassword}
          required
          hint="at least 8 characters"
        />
        <Field
          label="org name (optional)"
          value={orgName}
          onChange={setOrgName}
          placeholder="acme restaurant"
          hint="we'll derive one from your email if you skip this"
        />

        <button
          type="submit"
          disabled={signup.isPending || !email || password.length < 8}
          className="w-full rounded-md bg-primary text-primary-foreground py-2.5 text-sm font-medium hover:opacity-90 transition-opacity disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {signup.isPending ? "creating account…" : "create account"}
        </button>

        {signup.isError && (
          <p className="text-xs text-destructive text-center">
            {signup.error instanceof ApiError && signup.error.status === 409
              ? "an account with that email already exists. try logging in instead."
              : (signup.error as Error).message}
          </p>
        )}
      </form>

      <p className="mt-8 text-center text-sm text-muted-foreground">
        already have an account?{" "}
        <Link
          to="/login"
          className="text-foreground underline underline-offset-4 hover:opacity-70"
        >
          sign in
        </Link>
      </p>
    </div>
  );
}

function Field({
  label,
  type = "text",
  value,
  onChange,
  required,
  autoFocus,
  placeholder,
  hint,
}: {
  label: string;
  type?: string;
  value: string;
  onChange: (v: string) => void;
  required?: boolean;
  autoFocus?: boolean;
  placeholder?: string;
  hint?: string;
}) {
  return (
    <label className="block">
      <div className="text-xs text-muted-foreground mb-1">{label}</div>
      <input
        type={type}
        value={value}
        required={required}
        autoFocus={autoFocus}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-md border border-border bg-background/60 backdrop-blur-sm px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/60 focus:outline-none focus:ring-1 focus:ring-ring"
      />
      {hint && <div className="mt-1 text-xs text-muted-foreground/70">{hint}</div>}
    </label>
  );
}

export const signupRoute = createRoute({
  getParentRoute: () => publicLayoutRoute,
  path: "/signup",
  component: SignupPage,
});
