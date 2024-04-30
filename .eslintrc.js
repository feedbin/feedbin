module.exports = {
  "env": {
    "browser": true,
    "es2021": true
  },
  "extends": "eslint:recommended",
  "overrides": [
  ],
  "parserOptions": {
    "ecmaVersion": "latest",
    "sourceType": "module"
  },
  "plugins": ["prettier"],
  "rules": {
    "prettier/prettier": [
      "error",
      {
        "semi": false
      }
    ]
  }
}
