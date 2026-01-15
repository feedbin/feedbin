const defaultTheme = require("tailwindcss/defaultTheme")
const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    "./app/views/**/*.rb",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/views/**/*.{erb,html,rb}",
    "./app/components/**/*.{erb,html,rb}",
    "./app/assets/svg/*.svg",
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
        one:            "0px  1px 1px 0px var(--color-shadow-100)",
        two:            "0px  4px 6px 2px var(--color-shadow-100)",
        selected:       "0px  0px 0px 1px var(--color-blue-600)",
        "selected-700": "0px  0px 0px 1px var(--color-600)",
        "border-top":   "0px -1px 0px 0px var(--border-color)",
      },
      borderColor: {
        DEFAULT: "var(--border-color)",
      },
      colors: {
        base: "var(--color-base)",
        100: "var(--color-100)",
        200: "var(--color-200)",
        300: "var(--color-300)",
        400: "var(--color-400)",
        500: "var(--color-500)",
        600: "var(--color-600)",
        700: "var(--color-700)",
        sidebar: "var(--color-sidebar)",
        link: "var(--color-link)",
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
        day: {
          base:   "var(--day-color-base)",
          100:    "var(--day-color-100)",
          200:    "var(--day-color-200)",
          300:    "var(--day-color-300)",
          400:    "var(--day-color-400)",
          500:    "var(--day-color-500)",
          600:    "var(--day-color-600)",
          700:    "var(--day-color-700)",
          border: "var(--day-border-color)",
        },
        sunset: {
          base:   "var(--sunset-color-base)",
          100:    "var(--sunset-color-100)",
          200:    "var(--sunset-color-200)",
          300:    "var(--sunset-color-300)",
          400:    "var(--sunset-color-400)",
          500:    "var(--sunset-color-500)",
          600:    "var(--sunset-color-600)",
          700:    "var(--sunset-color-700)",
          border: "var(--sunset-border-color)",
        },
        dusk: {
          base:   "var(--dusk-color-base)",
          100:    "var(--dusk-color-100)",
          200:    "var(--dusk-color-200)",
          300:    "var(--dusk-color-300)",
          400:    "var(--dusk-color-400)",
          500:    "var(--dusk-color-500)",
          600:    "var(--dusk-color-600)",
          700:    "var(--dusk-color-700)",
          border: "var(--dusk-border-color)",
        },
        midnight: {
          base:   "var(--midnight-color-base)",
          100:    "var(--midnight-color-100)",
          200:    "var(--midnight-color-200)",
          300:    "var(--midnight-color-300)",
          400:    "var(--midnight-color-400)",
          500:    "var(--midnight-color-500)",
          600:    "var(--midnight-color-600)",
          700:    "var(--midnight-color-700)",
          border: "var(--midnight-border-color)",
        },
      },
      keyframes: {
        "slide-in": {
          "0%": { transform: "translateY(100vh)" },
          "100%": { transform: "translateY(0vh)" },
        },
        "slide-out": {
          "0%": { transform: "translateY(0vh)" },
          "100%": { transform: "translateY(100vh)" },
        },
        "slide-in-top": {
          "0%": { transform: "translateY(-34px)", opacity: "0.75" },
          "100%": { transform: "translateY(0)", opacity: "1" },
        },
        "slide-out-top": {
          "0%": { transform: "translateY(0)", opacity: "1" },
          "100%": { transform: "translateY(-34px)", opacity: "0.0" },
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
        "slide-in": "slide-in 0.3s ease-out forwards",
        "slide-out": "slide-out 0.25s ease-in forwards",
        "slide-in-top": "slide-in-top 0.3s ease-out forwards",
        "slide-out-top": "slide-out-top 0.25s ease-in forwards",
        "fade-in": "fade-in 0.3s linear forwards",
        "fade-out": "fade-out 0.25s linear forwards",
      },
    },
  },
  plugins: [
    plugin(function ({ addVariant }) {
      let pseudoVariants = [
        "checked",
        "focus",
        "active",
        "disabled",
        "checked:disabled",
      ].map((variant) =>
        Array.isArray(variant) ? variant : [variant, `&:${variant}`]
      );

      for (let [variantName, state] of pseudoVariants) {
        addVariant(`pg-${variantName}`, (ctx) => {
          let result = typeof state === "function" ? state(ctx) : state;
          return result.replace(/&(\S+)/, ":merge(.peer)$1 ~ .group &");
        });
      }
    }),
    plugin(function ({ addVariant }) {
      addVariant("pointer-coarse", "@media (pointer: coarse)");
      addVariant("pointer-fine", "@media (pointer: fine)");
    }),
    plugin(({ addVariant }) => {
      addVariant(`native`, [`.native &`, `&.native`]);
    }),
  ],
};
