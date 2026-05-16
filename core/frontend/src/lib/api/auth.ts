import { request } from "./client";
import type { LoginBody, Me, SignupBody } from "./types";

export const authApi = {
   signup: (body: SignupBody) =>
      request<Me>("/api/auth/signup", { method: "POST", json: body }),
   login: (body: LoginBody) =>
      request<Me>("/api/auth/login", { method: "POST", json: body }),
   logout: () => request<null>("/api/auth/logout", { method: "POST" }),
   me: () => request<Me>("/api/me"),
};
