import { request } from "./client";
import type {
   BucketSetup,
   BucketStatus,
   Me,
   Org,
   OrgMembershipDto,
   ProbeRoleBody,
   ProbeRoleResponse,
   SaveBucketKeysBody,
   SaveBucketRoleBody,
   UpdateOrgBody,
} from "./types";

export const orgApi = {
   // GET /api/org + PATCH /api/org — org settings
   getOrg: () => request<Org | null>("/api/org"),
   updateOrg: (body: UpdateOrgBody) =>
      request<Org | null>("/api/org", { method: "PATCH", json: body }),

   // multi-org: which orgs the current user belongs to + switching active org
   listMyOrgs: () => request<OrgMembershipDto[]>("/api/me/orgs"),
   switchOrg: (org_id: string) =>
      request<Me>("/api/me/switch-org", {
         method: "POST",
         json: { org_id },
      }),
   createOrg: (name: string) =>
      request<Me>("/api/orgs", { method: "POST", json: { name } }),

   // bucket connection (phase J)
   getBucket: () => request<BucketStatus>("/api/org/bucket"),
   getBucketSetup: (q: {
      bucket_name?: string;
      bucket_prefix?: string;
      bucket_region?: string;
      aws_account_id?: string;
   }) => {
      const params = new URLSearchParams();
      if (q.bucket_name) params.set("bucket_name", q.bucket_name);
      if (q.bucket_prefix) params.set("bucket_prefix", q.bucket_prefix);
      if (q.bucket_region) params.set("bucket_region", q.bucket_region);
      if (q.aws_account_id) params.set("aws_account_id", q.aws_account_id);
      const qs = params.toString();
      return request<BucketSetup>(
         `/api/org/bucket/setup${qs ? "?" + qs : ""}`,
      );
   },
   saveBucketRole: (body: SaveBucketRoleBody) =>
      request<BucketStatus>("/api/org/bucket/role", {
         method: "POST",
         json: body,
      }),
   probeBucketRole: (body: ProbeRoleBody) =>
      request<ProbeRoleResponse>("/api/org/bucket/role/probe", {
         method: "POST",
         json: body,
      }),
   saveBucketKeys: (body: SaveBucketKeysBody) =>
      request<BucketStatus>("/api/org/bucket/keys", {
         method: "POST",
         json: body,
      }),
   disconnectBucket: () =>
      request<BucketStatus>("/api/org/bucket", { method: "DELETE" }),
   ingestNow: () =>
      request<{ job_id: string }>("/api/org/bucket/ingest", {
         method: "POST",
      }),
};
