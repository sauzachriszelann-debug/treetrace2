// G7 tests: pure failure classification and backoff math (req 6 / D3).

import { describe, expect, test } from "vitest";
import {
  QueueFailureKind,
  backoffMs,
  classifyFailure,
  idempotentQueueTypes,
  photoPurposeFor,
  supportedQueueTypes,
  maxAutoAttempts,
} from "../service";

const http = (status, detail) => ({
  response: { status, data: detail !== undefined ? { detail } : undefined },
});
const noResponse = () => ({ request: {} });

describe("classifyFailure", () => {
  test("browser reports offline: provably not delivered, run aborts", () => {
    const info = classifyFailure(noResponse(), { idempotent: false, online: false });
    expect(info.kind).toBe(QueueFailureKind.network);
    expect(info.retryable).toBe(true);
    expect(info.requiresReview).toBe(false);
    expect(info.abortRun).toBe(true);
  });

  test("no response while online, idempotent type: safe retry", () => {
    const info = classifyFailure(noResponse(), { idempotent: true, online: true });
    expect(info.kind).toBe(QueueFailureKind.network);
    expect(info.retryable).toBe(true);
    expect(info.requiresReview).toBe(false);
    expect(info.abortRun).toBe(false);
  });

  test("no response while online, non-idempotent: AMBIGUOUS hold, never auto-retried", () => {
    const info = classifyFailure(noResponse(), { idempotent: false, online: true });
    expect(info.kind).toBe(QueueFailureKind.ambiguous);
    expect(info.requiresReview).toBe(true);
    expect(info.retryable).toBe(false);
    expect(info.message).toMatch(/duplicate/i);
  });

  test("401 aborts the run with the server message", () => {
    const info = classifyFailure(http(401, "Token expired"), { idempotent: true, online: true });
    expect(info.kind).toBe(QueueFailureKind.auth);
    expect(info.abortRun).toBe(true);
    expect(info.requiresReview).toBe(false);
    expect(info.message).toBe("Token expired");
  });

  test("402 quota is retryable, not a hold", () => {
    const info = classifyFailure(http(402, "Daily quota reached"), { idempotent: false, online: true });
    expect(info.kind).toBe(QueueFailureKind.quota);
    expect(info.retryable).toBe(true);
    expect(info.requiresReview).toBe(false);
  });

  test("403 role is a permanent hold", () => {
    const info = classifyFailure(http(403), { idempotent: true, online: true });
    expect(info.kind).toBe(QueueFailureKind.role);
    expect(info.requiresReview).toBe(true);
    expect(info.retryable).toBe(false);
  });

  test("409 conflict is a permanent hold - nothing merged", () => {
    const info = classifyFailure(http(409, "key belongs to a different tree"), { idempotent: true, online: true });
    expect(info.kind).toBe(QueueFailureKind.conflict);
    expect(info.requiresReview).toBe(true);
    expect(info.retryable).toBe(false);
    expect(info.message).toContain("key belongs to a different tree");
  });

  test("422/400 validation is a permanent hold", () => {
    for (const status of [400, 404, 422]) {
      const info = classifyFailure(http(status), { idempotent: true, online: true });
      expect(info.kind).toBe(QueueFailureKind.validation);
      expect(info.requiresReview).toBe(true);
      expect(info.retryable).toBe(false);
    }
  });

  test("5xx is retryable", () => {
    const info = classifyFailure(http(503), { idempotent: false, online: true });
    expect(info.kind).toBe(QueueFailureKind.server);
    expect(info.retryable).toBe(true);
    expect(info.requiresReview).toBe(false);
  });

  test("unexpected status becomes a hold", () => {
    const info = classifyFailure(http(418), { idempotent: true, online: true });
    expect(info.kind).toBe(QueueFailureKind.unknown);
    expect(info.requiresReview).toBe(true);
  });
});

describe("backoffMs", () => {
  test("grows exponentially from 30s", () => {
    expect(backoffMs(1)).toBe(30000);
    expect(backoffMs(2)).toBe(60000);
    expect(backoffMs(3)).toBe(120000);
  });

  test("caps at 30 minutes", () => {
    expect(backoffMs(8)).toBe(1800000);
    expect(backoffMs(50)).toBe(1800000);
  });

  test("auto attempt cap matches G6", () => {
    expect(maxAutoAttempts).toBe(5);
  });
});

describe("queue type contracts", () => {
  test("only G2/G4 types are idempotent", () => {
    expect([...idempotentQueueTypes].sort()).toEqual([
      "CREATE_TREE",
      "CREATE_TREE_SUBMISSION",
    ]);
  });

  test("UPDATE_TREE is excluded from the G7 queue (D2)", () => {
    expect(supportedQueueTypes.has("UPDATE_TREE")).toBe(false);
    expect([...supportedQueueTypes].sort()).toEqual([
      "CREATE_HEALTH_LOG",
      "CREATE_PLANTING_RECOMMENDATION",
      "CREATE_TREE",
      "CREATE_TREE_SUBMISSION",
      "SUBMIT_UNKNOWN",
    ]);
  });

  test("citizen submission photos use an upload purpose citizens are allowed", () => {
    // Backend gate: purpose=tree_photo is staff-only.
    expect(photoPurposeFor("CREATE_TREE_SUBMISSION")).toBe("unknown_species");
    expect(photoPurposeFor("SUBMIT_UNKNOWN")).toBe("unknown_species");
    expect(photoPurposeFor("CREATE_TREE")).toBe("tree_photo");
    expect(photoPurposeFor("CREATE_PLANTING_RECOMMENDATION")).toBe(
      "planting_submission",
    );
  });
});
