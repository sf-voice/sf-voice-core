// /login — sign in with email + password. same cream brand surface as
// /signup; failed login surfaces a single line of feedback.

import { useState } from "react";
import { Link, createRoute, useNavigate } from "@tanstack/react-router";
import { useLogin } from "@/lib/queries";
import { ApiError } from "@/lib/api";
import { publicLayoutRoute } from "./_public";

function LoginPage() {
  const navigate = useNavigate();
  const login = useLogin();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  return (
    <div className="w-full max-w-md">
      <header className="mb-8 text-center">
        <h1 className="font-display text-4xl tracking-tight text-foreground">
          welcome back.
        </h1>
        <p className="mt-3 text-muted-foreground text-sm">
          sign in to keep debugging.
        </p>
      </header>

      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          login.mutate(
            { email, password },
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
        />

        <button
          type="submit"
          disabled={login.isPending || !email || !password}
          className="w-full rounded-md bg-primary text-primary-foreground py-2.5 text-sm font-medium hover:opacity-90 transition-opacity disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {login.isPending ? "signing in…" : "sign in"}
        </button>

        {login.isError && (
          <p className="text-xs text-destructive text-center">
            {login.error instanceof ApiError && login.error.status === 401
              ? "wrong email or password."
              : (login.error as Error).message}
          </p>
        )}
      </form>

      <p className="mt-8 text-center text-sm text-muted-foreground">
        new here?{" "}
        <Link
          to="/signup"
          className="text-foreground underline underline-offset-4 hover:opacity-70"
        >
          create an account
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
}: {
  label: string;
  type?: string;
  value: string;
  onChange: (v: string) => void;
  required?: boolean;
  autoFocus?: boolean;
}) {
  return (
    <label className="block">
      <div className="text-xs text-muted-foreground mb-1">{label}</div>
      <input
        type={type}
        value={value}
        required={required}
        autoFocus={autoFocus}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-md border border-border bg-background/60 backdrop-blur-sm px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-ring"
      />
    </label>
  );
}

export const loginRoute = createRoute({
  getParentRoute: () => publicLayoutRoute,
  path: "/login",
  component: LoginPage,
});
