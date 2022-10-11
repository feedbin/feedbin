const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,html}',
    './app/components/**/*.{erb,html}'
  ],
  theme: {
    extend: {
    },
  },
  plugins: []
}
