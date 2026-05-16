import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, ApiError, type LoginBody, type SignupBody } from "../api";
import { qk } from "./keys";

export function useMe() {
   return useQuery({
      queryKey: qk.me(),
      queryFn: api.me,
      // 401 means logged out — short-circuit to null instead of error so
      // route guards can branch on `me === null`.
      retry: (failureCount, err) => {
         if (err instanceof ApiError && err.status === 401) return false;
         return failureCount < 1;
      },
   });
}

export function useSignup() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (body: SignupBody) => api.signup(body),
      onSuccess: (data) => qc.setQueryData(qk.me(), data),
   });
}

export function useLogin() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: (body: LoginBody) => api.login(body),
      onSuccess: (data) => qc.setQueryData(qk.me(), data),
   });
}

export function useLogout() {
   const qc = useQueryClient();
   return useMutation({
      mutationFn: () => api.logout(),
      onSuccess: () => {
         qc.setQueryData(qk.me(), null);
         qc.clear(); // drop all cached data on logout
      },
   });
}
