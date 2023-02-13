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
    data: {
      selected: "ui~='selected'",
    },
    screens: {
      sm: "480px",
      md: "700px",
      lg: "992px",
      xl: "1100px",
    },
    extend: {
      boxShadow: {
        "one": "0 1px 1px 0 var(--color-shadow-100)",
        "two": "0px 4px 6px 2px var(--color-shadow-100)",
      },
      borderColor: {
        DEFAULT: "var(--border-color)",
      },
      colors: {
        0:       "var(--color-base)",
        100:     "var(--color-100)",
        200:     "var(--color-200)",
        300:     "var(--color-300)",
        400:     "var(--color-400)",
        500:     "var(--color-500)",
        600:     "var(--color-600)",
        700:     "var(--color-700)",
        sidebar: "var(--color-sidebar)",
        link:    "var(--color-link)",
        light: {
          100: "var(--color-light-100)",
        },
        blue: {
          400: "var(--color-blue-400)",
          600: "var(--color-blue-600)",
          700: "var(--color-blue-700)",
        },
        orange: {
          600: "var(--color-orange-600)",
        },
        green: {
          600: "var(--color-green-600)",
          700: "var(--color-green-700)",
        },
        red: {
          200: "var(--color-red-200)",
          600: "var(--color-red-600)",
        },
      },
      spacing: {
        "0.5-fixed": "2px",
        "1-fixed":   "4px",
        "1.5-fixed": "6px",
        "2-fixed":   "8px",
        "2.5-fixed": "10px",
        "3-fixed":   "12px",
        "3.5-fixed": "14px",
        "4-fixed":   "16px",
        "5-fixed":   "20px",
        "6-fixed":   "24px",
        "7-fixed":   "28px",
        "8-fixed":   "32px",
        "9-fixed":   "36px",
        "10-fixed":  "40px",
        "11-fixed":  "44px",
        "12-fixed":  "48px",
        "14-fixed":  "56px",
        "16-fixed":  "64px",
        "20-fixed":  "80px",
        "24-fixed":  "96px",
        "28-fixed":  "112px",
        "32-fixed":  "128px"
      }
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

