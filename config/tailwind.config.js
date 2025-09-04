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
        selected:       "0px  0px 0px 1px rgb(var(--color-blue-600))",
        "selected-700": "0px  0px 0px 1px rgb(var(--color-600))",
        "border-top":   "0px -1px 0px 0px rgb(var(--border-color))",
      },
      borderColor: {
        DEFAULT: "rgb(var(--border-color))",
      },
      colors: {
        base: "rgb(var(--color-base))",
        100: "rgb(var(--color-100))",
        200: "rgb(var(--color-200))",
        300: "rgb(var(--color-300))",
        400: "rgb(var(--color-400))",
        500: "rgb(var(--color-500))",
        600: "rgb(var(--color-600))",
        700: "rgb(var(--color-700))",
        sidebar: "rgb(var(--color-sidebar))",
        link: "rgb(var(--color-link))",
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
        day: {
          base:   "rgb(var(--day-color-base))",
          100:    "rgb(var(--day-color-100))",
          200:    "rgb(var(--day-color-200))",
          300:    "rgb(var(--day-color-300))",
          400:    "rgb(var(--day-color-400))",
          500:    "rgb(var(--day-color-500))",
          600:    "rgb(var(--day-color-600))",
          700:    "rgb(var(--day-color-700))",
          border: "rgb(var(--day-border-color))",
        },
        sunset: {
          base:   "rgb(var(--sunset-color-base))",
          100:    "rgb(var(--sunset-color-100))",
          200:    "rgb(var(--sunset-color-200))",
          300:    "rgb(var(--sunset-color-300))",
          400:    "rgb(var(--sunset-color-400))",
          500:    "rgb(var(--sunset-color-500))",
          600:    "rgb(var(--sunset-color-600))",
          700:    "rgb(var(--sunset-color-700))",
          border: "rgb(var(--sunset-border-color))",
        },
        dusk: {
          base:   "rgb(var(--dusk-color-base))",
          100:    "rgb(var(--dusk-color-100))",
          200:    "rgb(var(--dusk-color-200))",
          300:    "rgb(var(--dusk-color-300))",
          400:    "rgb(var(--dusk-color-400))",
          500:    "rgb(var(--dusk-color-500))",
          600:    "rgb(var(--dusk-color-600))",
          700:    "rgb(var(--dusk-color-700))",
          border: "rgb(var(--dusk-border-color))",
        },
        midnight: {
          base:   "rgb(var(--midnight-color-base))",
          100:    "rgb(var(--midnight-color-100))",
          200:    "rgb(var(--midnight-color-200))",
          300:    "rgb(var(--midnight-color-300))",
          400:    "rgb(var(--midnight-color-400))",
          500:    "rgb(var(--midnight-color-500))",
          600:    "rgb(var(--midnight-color-600))",
          700:    "rgb(var(--midnight-color-700))",
          border: "rgb(var(--midnight-border-color))",
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
