import { createContext, useState, useContext, useEffect } from "react";
import { authApi } from "@/api/auth";
import { initDrafts } from "@/offline/drafts";

const AuthContext = createContext();
const ME_CACHE_KEY = "treetrace_me_cache";

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoadingAuth, setIsLoadingAuth] = useState(true);

  useEffect(() => {
    // G7 D5: hydrate durable G2/G4 drafts BEFORE any protected route can
    // render, so the synchronous sessionStorage readers see restored data.
    const token = localStorage.getItem("treetrace_token");
    if (token) {
      initDrafts()
        .catch(() => {})
        .finally(() => checkUserAuth());
    } else {
      initDrafts()
        .catch(() => {})
        .finally(() => setIsLoadingAuth(false));
    }
  }, []);

  const checkUserAuth = async () => {
    try {
      setIsLoadingAuth(true);
      const currentUser = await authApi.me();
      setUser(currentUser);
      setIsAuthenticated(true);
      try {
        localStorage.setItem(ME_CACHE_KEY, JSON.stringify(currentUser));
      } catch {
        /* cache unavailable: session still works */
      }
    } catch (error) {
      if (error?.response) {
        // The server explicitly rejected the credentials/token: clear them
        // (existing security behavior).
        localStorage.removeItem("treetrace_token");
        try {
          localStorage.removeItem(ME_CACHE_KEY);
        } catch {
          /* ignore */
        }
        setIsAuthenticated(false);
        setUser(null);
      } else {
        // G7 D4: NETWORK failure must not log the user out. Restore the
        // cached profile so offline startup keeps the session and role UI.
        try {
          const cached = localStorage.getItem(ME_CACHE_KEY);
          if (cached) {
            setUser(JSON.parse(cached));
            setIsAuthenticated(true);
            setIsLoadingAuth(false);
            return;
          }
        } catch {
          /* ignore */
        }
        setIsAuthenticated(false);
        setUser(null);
      }
    } finally {
      setIsLoadingAuth(false);
    }
  };

  const login = async (email, password) => {
    const { access_token } = await authApi.login(email, password);
    localStorage.setItem("treetrace_token", access_token);
    await checkUserAuth();
  };

  const logout = () => {
    localStorage.removeItem("treetrace_token");
    // Profile cache dies with the session; the offline queue and durable
    // drafts are intentionally untouched (G6/G7 safeguards 3 & 4).
    try {
      localStorage.removeItem(ME_CACHE_KEY);
    } catch {
      /* ignore */
    }
    setUser(null);
    setIsAuthenticated(false);
    window.location.href = "/login";
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated,
        isLoadingAuth,
        login,
        logout,
        checkUserAuth,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used within an AuthProvider");
  return context;
};
