// ESLint 9 flat config — restores `npm run lint`, which has been broken since
// the initial push (ESLint 9 requires a flat config file; none was ever
// committed). Uses only plugins already present in package.json:
//   @eslint/js, eslint-plugin-react, eslint-plugin-react-hooks,
//   eslint-plugin-react-refresh, globals.
// Rules stay close to the standard Vite/React template; deviations are
// commented. This file configures linting only — no application code changes.

import js from "@eslint/js";
import globals from "globals";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";

export default [
  { ignores: ["dist", "node_modules", "coverage"] },
  js.configs.recommended,
  react.configs.flat.recommended,
  react.configs.flat["jsx-runtime"],
  {
    files: ["**/*.{js,jsx}"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: { ...globals.browser, ...globals.node },
    },
    settings: { react: { version: "detect" } },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      // Version-proof: spread the eslintrc-style recommended ruleset, which
      // exists in every 5.x release (flat presets moved between versions).
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": [
        "warn",
        { allowConstantExport: true },
      ],
      // This codebase has never used PropTypes (plain JS components with
      // destructured props); the plugin default would flag every component.
      "react/prop-types": "off",
      // Underscore-prefixed names are intentional (unused params/vars).
      "no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },
];
