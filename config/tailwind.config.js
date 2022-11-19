const defaultTheme = require("tailwindcss/defaultTheme")
const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/views/**/*.{erb,html}",
    "./app/components/**/*.{erb,html,rb}",
    "./test/components/**/*.{erb,html,rb}"
  ],
  theme: {
    extend: {
      borderColor: {
        DEFAULT: "var(--border-color)",
        100: "var(--color-100)",
        200: "var(--color-200)",
        300: "var(--color-300)",
        400: "var(--color-400)",
        500: "var(--color-500)",
        600: "var(--color-600)",
        700: "var(--color-700)",
      },
      textColor: {
        400: "var(--color-400)",
        500: "var(--color-500)",
        600: "var(--color-600)",
        700: "var(--color-700)",
      },
      backgroundColor: {
        100: "var(--color-100)",
        200: "var(--color-200)",
        300: "var(--color-300)",
        400: "var(--color-400)",
        500: "var(--color-500)",
        600: "var(--color-600)",
        700: "var(--color-700)",
        "light-100": "var(--color-light-100)",
      },
      colors: {
        "day": {
          DEFAULT: "#FFFFFF",
          100:     "#f5f5f7",
          200:     "#e9e9eb",
          300:     "#bdbfc3",
          400:     "#91959b",
          500:     "#707680",
          600:     "#39404b",
          700:     "#0d1623",
        },
        "sunset": {
          DEFAULT: "#f5f2eb",
          100:     "#ebe8e2",
          200:     "#dfdcd6",
          300:     "#b8b6b0",
          400:     "#8e8c88",
          500:     "#6e6d69",
          600:     "#3b3a38",
          700:     "#191818",
        },
        "dusk": {
          DEFAULT: "#262626",
          100:     "#2d2d2d",
          200:     "#353535",
          300:     "#4d4d4d",
          400:     "#707070",
          500:     "#8c8c8c",
          600:     "#d4d4d4",
          700:     "#f6f6f6",
        },
        "midnight": {
          DEFAULT: "black",
          100:     "#141414",
          200:     "#242424",
          300:     "#3b3b3b",
          400:     "#595959",
          500:     "#757575",
          600:     "#bababa",
          700:     "#f5f5f5",
        },
        "blue": {
          400: "#619EEC",
          600: "#0867E2",
          700: "#0755B9",
        },
        "orange": {
          600: "#E96A0E",
        },
        "green": {
          600: "#07AC47",
          700: "#068D3B",
        },
        "red": {
          200: "#F8E7EA",
          600: "#BB0B2F",
        },
      },
    },
  },
  plugins: [
    plugin(function ({ addVariant }) {
      let pseudoVariants = [
        "checked", "focus", "active", "disabled"
      ].map((variant) =>
        Array.isArray(variant) ? variant : [variant, `&:${variant}`],
      );

      for (let [variantName, state] of pseudoVariants) {
        addVariant(`pg-${variantName}`, (ctx) => {
          let result = typeof state === "function" ? state(ctx) : state;
          return result.replace(/&(\S+)/, ":merge(.peer)$1 ~ .group &");
        });
      }
    }),
  ]
}

