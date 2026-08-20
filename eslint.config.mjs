import { dirname } from "path";
import { fileURLToPath } from "url";
import { FlatCompat } from "@eslint/eslintrc";
import security from "eslint-plugin-security";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
});

const eslintConfig = [
  ...compat.extends("next/core-web-vitals", "next/typescript"),

  // SAST (checklist §33): flags eval/child_process, unsafe regex (ReDoS),
  // non-literal fs paths, object-injection sinks and weak randomness.
  {
    files: ["app/**/*.{ts,tsx}", "components/**/*.{ts,tsx}", "lib/**/*.{ts,tsx}", "hooks/**/*.{ts,tsx}", "db/**/*.ts", "middleware.ts"],
    plugins: { security },
    rules: {
      ...security.configs.recommended.rules,
      // Noisy on ordinary TypeScript record access; tenant isolation is enforced by RLS,
      // and every dynamic key in this codebase is a typed enum/uuid, not raw user input.
      "security/detect-object-injection": "off",
    },
  },

  {
    ignores: [
      "node_modules/**",
      ".next/**",
      "out/**",
      "build/**",
      "next-env.d.ts",
      "scripts/_qa-*.mjs",
      // Vendored Claude Code skill content, not application code. It is CommonJS and trips
      // no-require-imports, which made `npm run lint` exit 1 on a clean tree — so the PR
      // template's "lint is clean locally" gate could not honestly be ticked by anyone, and
      // a gate nobody can pass is a gate everybody learns to ignore.
      "skills/**",
      // Android/Gradle build output.
      "android/**",
    ],
  },
];

export default eslintConfig;
