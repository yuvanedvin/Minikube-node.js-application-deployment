module.exports = {
  env: {
    node: true,
    es2021: true,
    jest: true,
  },
  extends: ["eslint:recommended"],
  parserOptions: {
    ecmaVersion: "latest",
  },
  rules: {
    "no-console": "off",        // We use console for structured logging
    "no-unused-vars": "warn",
    "no-undef": "error",
    "semi": ["warn", "always"],
  },
};