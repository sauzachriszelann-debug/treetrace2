// G7 tests: authentication must survive network failures and never be
// broken by the offline changes (D4, requirement 10).

import { describe, expect, test, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

vi.mock("@/api/auth", () => ({
  authApi: { me: vi.fn(), login: vi.fn() },
}));

import { authApi } from "@/api/auth";
import { AuthProvider, useAuth } from "@/lib/AuthContext";

function Probe() {
  const { isAuthenticated, user, isLoadingAuth } = useAuth();
  if (isLoadingAuth) return <div>loading</div>;
  return (
    <div>
      auth:{String(isAuthenticated)}|role:{user?.role ?? "none"}
    </div>
  );
}

const renderAuth = () =>
  render(
    <AuthProvider>
      <Probe />
    </AuthProvider>,
  );

describe("startup auth with an existing token", () => {
  test("NETWORK failure does not log the user out - cached profile is restored (D4)", async () => {
    localStorage.setItem("treetrace_token", "jwt-token");
    localStorage.setItem(
      "treetrace_me_cache",
      JSON.stringify({ id: 1, role: "field_worker" }),
    );
    const networkError = new Error("Network Error"); // no .response
    authApi.me.mockRejectedValue(networkError);

    renderAuth();

    await waitFor(() => {
      expect(screen.getByText(/auth:true\|role:field_worker/)).toBeInTheDocument();
    });
    // The token survives a network failure.
    expect(localStorage.getItem("treetrace_token")).toBe("jwt-token");
  });

  test("an explicit 401 still clears the session (security preserved)", async () => {
    localStorage.setItem("treetrace_token", "expired-jwt");
    localStorage.setItem("treetrace_me_cache", JSON.stringify({ id: 1, role: "admin" }));
    const unauthorized = new Error("401");
    unauthorized.response = { status: 401 };
    authApi.me.mockRejectedValue(unauthorized);

    renderAuth();

    await waitFor(() => {
      expect(screen.getByText(/auth:false\|role:none/)).toBeInTheDocument();
    });
    expect(localStorage.getItem("treetrace_token")).toBeNull();
    expect(localStorage.getItem("treetrace_me_cache")).toBeNull();
  });

  test("a successful lookup caches the profile for later offline starts", async () => {
    localStorage.setItem("treetrace_token", "jwt-token");
    authApi.me.mockResolvedValue({ id: 2, role: "citizen" });

    renderAuth();

    await waitFor(() => {
      expect(screen.getByText(/auth:true\|role:citizen/)).toBeInTheDocument();
    });
    expect(
      JSON.parse(localStorage.getItem("treetrace_me_cache")).role,
    ).toBe("citizen");
  });

  test("startup without a token stays logged out", async () => {
    renderAuth();
    await waitFor(() => {
      expect(screen.getByText(/auth:false\|role:none/)).toBeInTheDocument();
    });
    expect(authApi.me).not.toHaveBeenCalled();
  });
});
