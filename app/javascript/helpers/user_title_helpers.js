export function userTitle(id, defaultTitle) {
  return window.feedbin.data.user_titles[id] ?? defaultTitle
}
