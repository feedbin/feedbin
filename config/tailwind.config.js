const defaultTheme = require("tailwindcss/defaultTheme")
const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    "./app/views/**/*.rb",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/views/**/*.{erb,html,rb}",
    "./app/components/**/*.{erb,html,rb}",
    "./test/components/**/*.{erb,html,rb}"
  ],
  theme: {
    data: {
      selected: `ui~="selected"`,
    },
    screens: {
      sm: "480px",
      md: "700px",
      lg: "992px",
      xl: "1100px",
    },
    extend: {
      boxShadow: {
        "one": "0 1px 1px 0          var(--color-shadow-100)",
        "two": "0px 4px 6px 2px      var(--color-shadow-100)",
        "selected": "0px 0px 0px 1px rgb(var(--color-blue-600))",
      },
      borderColor: {
        DEFAULT: "rgb(var(--border-color))",
      },
      colors: {
        base:    "rgb(var(--color-base))",
        100:     "rgb(var(--color-100))",
        200:     "rgb(var(--color-200))",
        300:     "rgb(var(--color-300))",
        400:     "rgb(var(--color-400))",
        500:     "rgb(var(--color-500))",
        600:     "rgb(var(--color-600))",
        700:     "rgb(var(--color-700))",
        sidebar: "rgb(var(--color-sidebar))",
        link:    "rgb(var(--color-link))",
        light: {
          100: "rgb(var(--color-light-100))",
        },
        blue: {
          400: "rgb(var(--color-blue-400))",
          600: "rgb(var(--color-blue-600))",
          700: "rgb(var(--color-blue-700))",
        },
        orange: {
          600: "rgb(var(--color-orange-600))",
        },
        green: {
          600: "rgb(var(--color-green-600))",
          700: "rgb(var(--color-green-700))",
        },
        red: {
          200: "rgb(var(--color-red-200))",
          600: "rgb(var(--color-red-600))",
        },
      },
      keyframes: {
        "slide-in": {
          "0%": { transform: "translateY(100%)" },
          "100%": { transform: "translateY(0)" },
        },
        "slide-out": {
          "0%": { transform: "translateY(0)" },
          "100%": { transform: "translateY(100%)" },
        },
        "fade-in": {
          "0%": { opacity: "0" },
          "100%": { opacity: "1" },
        },
        "fade-out": {
          "0%": { opacity: "1" },
          "100%": { opacity: "0" },
        },
      },
      animation: {
        "slide-in": "slide-in 0.35s ease-out",
        "slide-out": "slide-out 0.25s ease-in",
        "fade-in": "fade-in 0.35s ease-in",
        "fade-out": "fade-out 0.25s ease-out",
      },
    },
  },
  plugins: [
    plugin(function ({ addVariant }) {
      let pseudoVariants = [
        "checked", "focus", "active", "disabled", "checked:disabled"
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
    plugin(({ addVariant }) => {
      addVariant(`native`, [`.native &`, `&.native`])
    }),
  ]
}

